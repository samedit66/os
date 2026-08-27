class
    OS_COMMAND

create
    make,
    make_shell

feature {NONE} -- Initialization

    make (
        a_executable: READABLE_STRING_GENERAL;
        a_arguments: ITERABLE [READABLE_STRING_GENERAL]
    )
            -- Describe execution of `a_executable` with copied `a_arguments`.
        require
            executable_not_empty: not a_executable.is_empty
            executable_has_no_nul: not a_executable.has_code (0)
            arguments_have_no_nul:
                across a_arguments as argument all not argument.has_code (0) end
        local
            argument_copy: STRING_32
        do
            create command_mutex.make
            require_valid_text (a_executable, "Executable")
            create executable.make_from_string_general (a_executable)
            create arguments.make (8)
            create input.make_empty
            across a_arguments as argument loop
                require_valid_text (argument, "Argument")
                create argument_copy.make_from_string_general (argument)
                arguments.extend (argument_copy)
            end
        ensure
            executable_set: executable.same_string_general (a_executable)
            not_started: not has_started
            not_finished: not finished
            can_start: can_start
            no_failures: not has_failures
        end

    make_shell (a_command: READABLE_STRING_GENERAL)
            -- Describe execution of `a_command` by the platform shell.
        require
            command_not_empty: not a_command.is_empty
            command_has_no_nul: not a_command.has_code (0)
        do
            require_valid_text (a_command, "Shell command")
            make (shell_executable, shell_arguments (a_command))
        end

feature -- Change

    set_input (a_input: READABLE_STRING_8)
            -- Use copied raw bytes as standard input for subsequent executions.
        require
            can_start: can_start
        local
            input_copy: STRING_8
            mutex_locked: BOOLEAN
        do
            create input_copy.make_from_string (a_input)
            command_mutex.lock
            mutex_locked := True
            if not can_start_unlocked then
                raise_client_failure ("Cannot change input while a command is running")
            end
            input := input_copy
            command_mutex.unlock
            mutex_locked := False
        ensure
            input_set: input.same_string (a_input)
        rescue
            if mutex_locked then
                command_mutex.unlock
            end
        end

    set_working_directory (a_directory: READABLE_STRING_GENERAL)
            -- Use a normalized absolute snapshot of `a_directory` for subsequent executions.
        require
            can_start: can_start
            directory_has_no_nul: not a_directory.has_code (0)
        local
            directory_path: PATH
            directory_copy: STRING_32
            mutex_locked: BOOLEAN
        do
            require_valid_text (a_directory, "Working directory")
            create directory_path.make_from_string (a_directory)
            directory_copy := directory_path.canonical_path.name.to_string_32
            command_mutex.lock
            mutex_locked := True
            if not can_start_unlocked then
                raise_client_failure ("Cannot change directory while a command is running")
            end
            working_directory := directory_copy
            command_mutex.unlock
            mutex_locked := False
        ensure
            working_directory_set: attached working_directory
        rescue
            if mutex_locked then
                command_mutex.unlock
            end
        end

feature -- Execution

    run
            -- Start an execution and wait for its terminal result.
        require
            can_start: can_start
        do
            start
            wait_for_exit
        ensure
            started: has_started
            finished: finished
        end

    start
            -- Start an execution without output handlers.
        require
            can_start: can_start
        do
            start_streaming (Void, Void)
        ensure
            started: has_started
        end

    start_streaming (
        a_stdout: detachable PROCEDURE [READABLE_STRING_8];
        a_stderr: detachable PROCEDURE [READABLE_STRING_8]
    )
            -- Start an execution and forward captured output chunks.
        require
            can_start: can_start
        local
            process: OS_PROCESS
            mutex_locked: BOOLEAN
        do
            command_mutex.lock
            mutex_locked := True
            if not can_start_unlocked then
                raise_client_failure ("Cannot start overlapping command executions")
            end
            create process.make (
                executable,
                arguments,
                a_stdout,
                a_stderr,
                working_directory,
                input
            )
            current_process := process
            has_started_state := True
            latest_execution_result := Void
            finished_state := process.is_finished
            if finished_state then
                latest_execution_result := process.execution_result
            end
            command_mutex.unlock
            mutex_locked := False
        ensure
            started: has_started
            current_execution_attached: attached current_process
        rescue
            if mutex_locked then
                command_mutex.unlock
            end
        end

    poll
            -- Update the recorded execution state without waiting.
        require
            started: has_started
        local
            process: OS_PROCESS
        do
            process := attached_process
            process.poll
            publish_if_current (process)
        ensure
            finished_is_stable: old finished implies finished
        end

    wait_for_exit
            -- Wait for child, I/O workers, cleanup, and result publication.
        require
            started: has_started
        local
            process: OS_PROCESS
        do
            process := attached_process
            process.wait
            publish_if_current (process)
        ensure
            finished: finished
        end

    terminate
            -- Request platform-dependent termination of the current child.
        require
            started: has_started
        local
            process: OS_PROCESS
        do
            process := attached_process
            process.terminate
            publish_if_current (process)
        end

feature -- Access

    execution_result: OS_PROCESS_EXECUTION_RESULT
            -- Terminal result of the latest execution.
        require
            finished: finished
        local
            snapshot: detachable OS_PROCESS_EXECUTION_RESULT
        do
            command_mutex.lock
            snapshot := latest_execution_result
            command_mutex.unlock
            check attached snapshot as completed_result then
                Result := completed_result
            end
        end

    failures: READABLE_INDEXABLE [OS_PROCESS_FAILURE]
            -- Defensive snapshot of failures from the latest execution.
        local
            process: detachable OS_PROCESS
            completed_result: detachable OS_PROCESS_EXECUTION_RESULT
            snapshot: ARRAYED_LIST [OS_PROCESS_FAILURE]
        do
            command_mutex.lock
            process := current_process
            completed_result := latest_execution_result
            command_mutex.unlock
            if attached completed_result as completed then
                Result := completed.failures
            elseif attached process as active_process then
                Result := active_process.failures
            else
                create snapshot.make (0)
                Result := snapshot
            end
        end

feature -- Status report

    has_started: BOOLEAN
            -- Has Current started at least one execution?
        do
            command_mutex.lock
            Result := has_started_state
            command_mutex.unlock
        end

    finished: BOOLEAN
            -- Is the terminal result of the latest execution recorded?
        do
            command_mutex.lock
            Result := finished_state
            command_mutex.unlock
        end

    can_start: BOOLEAN
            -- May a new sequential execution be started?
        do
            command_mutex.lock
            Result := can_start_unlocked
            command_mutex.unlock
        ensure
            definition: Result = (not has_started or else finished)
        end

    successful: BOOLEAN
            -- Did the latest execution complete successfully?
        require
            finished: finished
        do
            Result := execution_result.successful
        ensure
            definition: Result = execution_result.successful
        end

    has_failures: BOOLEAN
            -- Have failures been recorded for the latest execution?
        local
            snapshot: READABLE_INDEXABLE [OS_PROCESS_FAILURE]
        do
            snapshot := failures
            Result := snapshot.lower <= snapshot.upper
        end

feature {NONE} -- State publication

    attached_process: OS_PROCESS
            -- Current execution process.
        local
            snapshot: detachable OS_PROCESS
        do
            command_mutex.lock
            snapshot := current_process
            command_mutex.unlock
            check attached snapshot as process then
                Result := process
            end
        end

    publish_if_current (a_process: OS_PROCESS)
            -- Publish `a_process` if it is still Current's execution.
        do
            command_mutex.lock
            if current_process = a_process and then a_process.is_finished then
                latest_execution_result := a_process.execution_result
                finished_state := True
            end
            command_mutex.unlock
        end

    can_start_unlocked: BOOLEAN
            -- `can_start` while `command_mutex` is held.
        do
            Result := not has_started_state or else finished_state
        end

feature {NONE} -- Validation

    require_valid_text (
        a_text: READABLE_STRING_GENERAL;
        a_name: READABLE_STRING_8
    )
            -- Reject embedded NUL independently of assertion settings.
        do
            if a_text.has_code (0) then
                raise_client_failure (a_name + " contains a NUL character")
            end
        end

    raise_client_failure (a_message: READABLE_STRING_8)
            -- Report a violated runtime lifecycle or text obligation.
        do
            (create {EXCEPTIONS}).raise (a_message)
        end

feature {NONE} -- Shell implementation

    shell_executable: STRING_32
            -- Executable for the platform command shell.
        local
            environment: EXECUTION_ENVIRONMENT
        do
            if {PLATFORM}.is_windows then
                create environment
                if attached environment.item ("COMSPEC") as command_processor and then
                    not command_processor.is_empty
                then
                    Result := command_processor.to_string_32
                else
                    create Result.make_from_string_general ("cmd.exe")
                end
            else
                create Result.make_from_string_general ("/bin/sh")
            end
        ensure
            not_empty: not Result.is_empty
        end

    shell_arguments (a_command: READABLE_STRING_GENERAL): ARRAYED_LIST [READABLE_STRING_GENERAL]
            -- Arguments that ask the platform shell to interpret `a_command`.
        require
            command_not_empty: not a_command.is_empty
            command_has_no_nul: not a_command.has_code (0)
        do
            if {PLATFORM}.is_windows then
                create Result.make (4)
                Result.extend ("/D")
                Result.extend ("/S")
                Result.extend ("/C")
            else
                create Result.make (2)
                Result.extend ("-c")
            end
            Result.extend (a_command)
        ensure
            command_is_last: Result.last = a_command
        end

feature {NONE} -- Implementation

    executable: STRING_32
            -- Copied executable name or path.

    arguments: ARRAYED_LIST [STRING_32]
            -- Copied argument vector.

    working_directory: detachable STRING_32
            -- Canonical directory snapshot for subsequent executions.

    input: STRING_8
            -- Raw standard-input bytes for subsequent executions.

    command_mutex: MUTEX
            -- Lock protecting configuration and current execution publication.

    current_process: detachable OS_PROCESS
            -- Process owned by the latest execution.

    latest_execution_result: detachable OS_PROCESS_EXECUTION_RESULT
            -- Published terminal result of the latest execution.

    has_started_state: BOOLEAN
            -- Has at least one execution been started?

    finished_state: BOOLEAN
            -- Is the latest execution terminal and published?

invariant
    executable_not_empty: not executable.is_empty
    finished_requires_start: finished_state implies has_started_state
    not_started_has_no_process:
        not has_started_state implies current_process = Void
    active_has_process:
        has_started_state and not finished_state implies attached current_process
    active_has_no_result:
        has_started_state and not finished_state implies latest_execution_result = Void
    finished_has_process:
        finished_state implies attached current_process
    finished_has_result:
        finished_state implies attached latest_execution_result

end
