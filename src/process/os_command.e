note

	description:
	"[
        Reusable command configuration that launches and observes one native
        process at a time, with optional input, output callbacks, and shell
        execution. Each command owns an environment snapshot. A bare executable
        is resolved through that snapshot's PATH on both Unix and Windows,
        avoiding the platform difference where CreateProcessW otherwise searches
        with the parent process environment.
    ]"
	author: "samedit66 <samedit66@yandex.ru>"
	library: "os"
	warning: "The command owns each started execution until autonomous cleanup completes."

class OS_COMMAND

create

	make,
	make_shell

feature {NONE} -- Initialization

	make (a_executable: READABLE_STRING_GENERAL; a_arguments: ITERABLE [READABLE_STRING_GENERAL])
			-- Describe execution of `a_executable` with copied `a_arguments`.
		require
			executable_not_empty: not a_executable.is_empty
			executable_has_no_nul: not a_executable.has_code (0)
			arguments_have_no_nul: across a_arguments as argument all not argument.has_code (0) end
		local
			argument_copy: STRING_32
		do
			create command_mutex.make
			create environment.make
			create executable.make_from_string_general (a_executable)
			create arguments.make (8)
			create input.make_empty
			stdin_mode := stdin_pipe_mode
			stdout_mode := output_capture_mode
			stderr_mode := output_capture_mode
			across
				a_arguments
			as
				argument
			loop
				create argument_copy.make_from_string_general (argument)
				arguments.extend (argument_copy)
			end
		ensure
			executable_set: executable.same_string_general (a_executable)
			not_started: not has_started
			not_finished: not finished
			can_start: can_start
		end

	make_shell (a_command: READABLE_STRING_GENERAL)
			-- Describe execution of `a_command` by the platform shell.
		require
			command_not_empty: not a_command.is_empty
			command_has_no_nul: not a_command.has_code (0)
		do
			make (shell_executable, shell_arguments (a_command))
		end

feature -- Change

	capture_stdout
			-- Capture standard output in the result and make it available to a callback.
		require
			can_start: can_start
		do
			set_stdout_mode (output_capture_mode)
		end

	inherit_stdout
			-- Send standard output directly to Current's inherited destination.
			-- Inherited bytes are deliberately not buffered in Eiffel memory.
		require
			can_start: can_start
		do
			set_stdout_mode (output_inherit_mode)
		end

	discard_stdout
			-- Send standard output to the platform null device.
		require
			can_start: can_start
		do
			set_stdout_mode (output_discard_mode)
		end

	capture_stderr
			-- Capture standard error separately in the result and callback.
		require
			can_start: can_start
		do
			set_stderr_mode (output_capture_mode)
		end

	inherit_stderr
			-- Send standard error directly to Current's inherited destination.
			-- Inherited bytes are deliberately not buffered in Eiffel memory.
		require
			can_start: can_start
		do
			set_stderr_mode (output_inherit_mode)
		end

	discard_stderr
			-- Send standard error to the platform null device.
		require
			can_start: can_start
		do
			set_stderr_mode (output_discard_mode)
		end

	merge_stderr
			-- Redirect standard error to the configured standard-output destination.
			-- When stdout is captured, merged bytes and callbacks belong to stdout;
			-- there is no separate stderr snapshot or stderr callback.
		require
			can_start: can_start
		do
			set_stderr_mode (stderr_merge_mode)
		end

	inherit_stdin
			-- Connect the child directly to Current's inherited standard input.
			-- No Eiffel writer is created in this mode.
			-- On POSIX, `run` temporarily gives an inherited terminal to the child
			-- process group and restores it afterward. Asynchronous `start` and
			-- `start_streaming` reject terminal stdin; inherited nonterminal input
			-- remains valid. This API intentionally does not allocate a PTY.
		require
			can_start: can_start
		do
			set_stdin_mode (stdin_inherit_mode)
		end

	set_timeout_milliseconds (a_timeout: INTEGER)
			-- Limit the overall execution to `a_timeout` milliseconds.
			-- The deadline covers process execution and inherited capture pipes.
		require
			can_start: can_start
			positive_timeout: a_timeout > 0
		local
			mutex_locked: BOOLEAN
		do
			command_mutex.lock
			mutex_locked := True
			if not can_start_unlocked then
				raise_client_failure ("Cannot change timeout while a command is running")
			end
			timeout_milliseconds := a_timeout
			command_mutex.unlock
			mutex_locked := False
		rescue
			if mutex_locked then
				command_mutex.unlock
			end
		end

	set_timeout_seconds (a_timeout: INTEGER)
			-- Limit the overall execution to `a_timeout` seconds.
			-- The deadline covers process execution and inherited capture pipes.
		require
			can_start: can_start
			positive_timeout: a_timeout > 0
			timeout_fits_milliseconds: a_timeout <= {INTEGER}.max_value // 1_000
		do
			set_timeout_milliseconds (a_timeout * 1_000)
		end

	clear_timeout
			-- Remove the overall execution deadline.
		require
			can_start: can_start
		local
			mutex_locked: BOOLEAN
		do
			command_mutex.lock
			mutex_locked := True
			if not can_start_unlocked then
				raise_client_failure ("Cannot change timeout while a command is running")
			end
			timeout_milliseconds := 0
			command_mutex.unlock
			mutex_locked := False
		rescue
			if mutex_locked then
				command_mutex.unlock
			end
		end

	set_input (a_input: READABLE_STRING_8)
			-- Use copied raw bytes through a pipe as input for subsequent executions.
			-- This also switches back from inherited stdin to piped stdin.
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
			stdin_mode := stdin_pipe_mode
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

	set_environment_variable (a_name, a_value: READABLE_STRING_GENERAL)
			-- Set copied environment variable `a_name` for subsequent executions.
			-- Names are case-sensitive on Unix and case-insensitive on Windows.
		require
			can_start: can_start
			name_not_empty: not a_name.is_empty
			name_has_no_nul: not a_name.has_code (0)
			name_has_no_equal: not a_name.has ('=')
			value_has_no_nul: not a_value.has_code (0)
		local
			mutex_locked: BOOLEAN
		do
			command_mutex.lock
			mutex_locked := True
			if not can_start_unlocked then
				raise_client_failure ("Cannot change environment while a command is running")
			end
			environment.set_variable (a_name, a_value)
			command_mutex.unlock
			mutex_locked := False
		ensure
			variable_set: environment.has_variable (a_name)
			value_set: environment.variable (a_name).same_string_general (a_value)
		rescue
			if mutex_locked then
				command_mutex.unlock
			end
		end

	unset_environment_variable (a_name: READABLE_STRING_GENERAL)
			-- Remove environment variable `a_name` from subsequent executions.
			-- Names are case-sensitive on Unix and case-insensitive on Windows.
		require
			can_start: can_start
			name_not_empty: not a_name.is_empty
			name_has_no_nul: not a_name.has_code (0)
			name_has_no_equal: not a_name.has ('=')
		local
			mutex_locked: BOOLEAN
		do
			command_mutex.lock
			mutex_locked := True
			if not can_start_unlocked then
				raise_client_failure ("Cannot change environment while a command is running")
			end
			environment.unset_variable (a_name)
			command_mutex.unlock
			mutex_locked := False
		ensure
			variable_absent: not environment.has_variable (a_name)
		rescue
			if mutex_locked then
				command_mutex.unlock
			end
		end

	clear_environment
			-- Remove all environment variables from subsequent executions.
			-- No PATH or Windows SYSTEMROOT value is injected after this call.
		require
			can_start: can_start
		local
			mutex_locked: BOOLEAN
		do
			command_mutex.lock
			mutex_locked := True
			if not can_start_unlocked then
				raise_client_failure ("Cannot change environment while a command is running")
			end
			environment.clear
			command_mutex.unlock
			mutex_locked := False
		rescue
			if mutex_locked then
				command_mutex.unlock
			end
		end

	prepend_to_path (a_directory: READABLE_STRING_GENERAL)
			-- Prepend `a_directory` to PATH for lookup and child execution.
			-- PATH uses ':' on Unix and ';' on Windows. An absent or empty PATH
			-- becomes exactly `a_directory`, without an implicit current directory.
		require
			can_start: can_start
			directory_not_empty: not a_directory.is_empty
			directory_has_no_nul: not a_directory.has_code (0)
		local
			mutex_locked: BOOLEAN
		do
			command_mutex.lock
			mutex_locked := True
			if not can_start_unlocked then
				raise_client_failure ("Cannot change environment while a command is running")
			end
			environment.prepend_to_path (a_directory)
			command_mutex.unlock
			mutex_locked := False
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
			start_execution (Void, Void, True)
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

	start_streaming (a_stdout: detachable PROCEDURE [READABLE_STRING_8]; a_stderr: detachable PROCEDURE [READABLE_STRING_8])
			-- Start an execution and forward captured output chunks.
		require
			can_start: can_start
			stdout_callback_requires_capture: attached a_stdout implies stdout_is_captured
			stderr_callback_requires_capture: attached a_stderr implies stderr_is_captured
				-- Each attached callback must eventually return. A callback executes on
				-- its stream worker; waiting for it is part of execution completion.
		do
			start_execution (a_stdout, a_stderr, False)
		ensure
			started: has_started
			current_execution_attached: attached current_process
				-- Completion additionally relies on every attached callback returning;
				-- this client obligation cannot be expressed as a runtime assertion.
		end

	wait_for_exit
			-- Wait until autonomous cleanup and result publication have completed.
		require
			started: has_started
		do
			attached_process.wait
		ensure
			finished: finished
		end

	terminate
			-- Force termination of the current managed process tree.
			-- POSIX descendants that deliberately escape the launch process group
			-- with setsid/setpgid are outside this containment guarantee.
		require
			started: has_started
		local
			process: OS_PROCESS
		do
			process := attached_process
			process.terminate
		end

feature -- Access

	executable_path (a_name: READABLE_STRING_GENERAL): STRING_32
			-- Absolute normalized path of executable `a_name` for Current.
			-- A bare name uses Current's PATH on both Unix and Windows. Relative
			-- PATH entries use Current's configured working directory.
		require
			name_not_empty: not a_name.is_empty
			name_has_no_nul: not a_name.has_code (0)
			executable_exists: has_executable (a_name)
		local
			launch_directory: PATH
			executable_snapshot: detachable STRING_32
		do
			command_mutex.lock
			launch_directory := effective_working_directory_unlocked
			if environment.has_executable_in (a_name, launch_directory) then
				executable_snapshot := environment.executable_path_in (a_name, launch_directory)
			end
			command_mutex.unlock
			check
				attached executable_snapshot as resolved
			then
				Result := resolved
			end
		end

	exit_code: INTEGER
			-- Child exit code from the latest execution.
		require
			finished: finished
			has_exit_code: has_exit_code
		do
			Result := latest_execution_result.exit_code
		ensure
			definition: Result = latest_execution_result.exit_code
		end

	stdout: READABLE_STRING_8
			-- Captured standard-output bytes from the latest execution.
		require
			finished: finished
			was_captured: stdout_was_captured
		do
			Result := latest_execution_result.stdout
		ensure
			definition: Result.same_string (latest_execution_result.stdout)
		end

	stderr: READABLE_STRING_8
			-- Captured standard-error bytes from the latest execution.
		require
			finished: finished
			was_captured: stderr_was_captured
		do
			Result := latest_execution_result.stderr
		ensure
			definition: Result.same_string (latest_execution_result.stderr)
		end

	failures: READABLE_INDEXABLE [OS_PROCESS_FAILURE]
			-- Defensive snapshot of failures from the latest execution.
		require
			finished: finished
		do
			Result := latest_execution_result.failures
		ensure
			count_preserved: Result.upper - Result.lower + 1 = latest_execution_result.failures.upper - latest_execution_result.failures.lower + 1
		end

feature -- Status report

	stdout_is_captured: BOOLEAN
			-- Will standard output be captured for the next execution?
		do
			command_mutex.lock
			Result := stdout_mode = output_capture_mode
			command_mutex.unlock
		end

	stderr_is_captured: BOOLEAN
			-- Will standard error be captured separately for the next execution?
		do
			command_mutex.lock
			Result := stderr_mode = output_capture_mode
			command_mutex.unlock
		end

	has_executable (a_name: READABLE_STRING_GENERAL): BOOLEAN
			-- Does executable `a_name` resolve for Current?
			-- A bare name uses Current's PATH on both Unix and Windows. No parent
			-- PATH fallback is used after PATH is removed or the environment cleared.
		require
			name_not_empty: not a_name.is_empty
			name_has_no_nul: not a_name.has_code (0)
		local
			launch_directory: PATH
		do
			command_mutex.lock
			launch_directory := effective_working_directory_unlocked
			Result := environment.has_executable_in (a_name, launch_directory)
			command_mutex.unlock
		end

	has_started: BOOLEAN
			-- Has Current started at least one execution?
		do
			command_mutex.lock
			Result := has_started_state
			command_mutex.unlock
		end

	finished: BOOLEAN
			-- Is the latest execution's terminal result available?
		local
			process: detachable OS_PROCESS
		do
			command_mutex.lock
			process := current_process
			command_mutex.unlock
			Result := attached process as active_process and then active_process.is_finished
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
			Result := latest_execution_result.successful
		ensure
			definition: Result = latest_execution_result.successful
		end

	has_failures: BOOLEAN
			-- Have failures been recorded for the latest execution?
		require
			finished: finished
		do
			Result := latest_execution_result.has_failures
		ensure
			definition: Result = latest_execution_result.has_failures
		end

	was_launched: BOOLEAN
			-- Was a child process successfully launched in the latest execution?
		require
			finished: finished
		do
			Result := latest_execution_result.was_launched
		ensure
			definition: Result = latest_execution_result.was_launched
		end

	has_exit_code: BOOLEAN
			-- Is a child completion code available for the latest execution?
		require
			finished: finished
		do
			Result := latest_execution_result.has_exit_code
		ensure
			definition: Result = latest_execution_result.has_exit_code
		end

	stdout_was_captured: BOOLEAN
			-- Was standard output captured in the latest execution?
		require
			finished: finished
		do
			Result := latest_execution_result.stdout_was_captured
		ensure
			definition: Result = latest_execution_result.stdout_was_captured
		end

	stderr_was_captured: BOOLEAN
			-- Was standard error captured separately in the latest execution?
		require
			finished: finished
		do
			Result := latest_execution_result.stderr_was_captured
		ensure
			definition: Result = latest_execution_result.stderr_was_captured
		end

	stderr_was_merged: BOOLEAN
			-- Was standard error redirected to standard output in the latest execution?
		require
			finished: finished
		do
			Result := latest_execution_result.stderr_was_merged
		ensure
			definition: Result = latest_execution_result.stderr_was_merged
		end

	was_terminated_by_client: BOOLEAN
			-- Did a client termination request end the latest execution?
		require
			finished: finished
		do
			Result := latest_execution_result.was_terminated_by_client
		ensure
			definition: Result = latest_execution_result.was_terminated_by_client
		end

	was_timed_out: BOOLEAN
			-- Did the latest execution exceed its configured deadline?
		require
			finished: finished
		do
			Result := latest_execution_result.was_timed_out
		ensure
			definition: Result = latest_execution_result.was_timed_out
		end

	output_was_cut_off: BOOLEAN
			-- Was captured output from the latest execution stopped before EOF?
		require
			finished: finished
		do
			Result := latest_execution_result.output_was_cut_off
		ensure
			definition: Result = latest_execution_result.output_was_cut_off
		end

feature {NONE} -- State publication

	start_execution (a_stdout: detachable PROCEDURE [READABLE_STRING_8]; a_stderr: detachable PROCEDURE [READABLE_STRING_8]; a_allow_terminal_stdin: BOOLEAN)
			-- Start one execution, allowing a foreground terminal handoff only for `run`.
		local
			process: OS_PROCESS
			launch_directory: PATH
			resolved_executable: STRING_32
			mutex_locked: BOOLEAN
		do
			command_mutex.lock
			mutex_locked := True
			if not can_start_unlocked then
				raise_client_failure ("Cannot start overlapping command executions")
			end
			launch_directory := effective_working_directory_unlocked
			if environment.has_executable_in (executable, launch_directory) then
				resolved_executable := environment.executable_path_in (executable, launch_directory)
				create process.make (resolved_executable, arguments, a_stdout, a_stderr, working_directory, input, environment.entries, stdin_mode, stdout_mode, stderr_mode, timeout_milliseconds, a_allow_terminal_stdin)
			else
				create process.make_unresolved (executable, stdout_mode = output_capture_mode, stderr_mode = output_capture_mode, stderr_mode = stderr_merge_mode)
			end
			current_process := process
			has_started_state := True
			command_mutex.unlock
			mutex_locked := False
		rescue
			if mutex_locked then
				command_mutex.unlock
			end
		end

	set_stdin_mode (a_mode: INTEGER)
			-- Set the native stdin routing mode.
		require
			valid_mode: a_mode = stdin_pipe_mode or else a_mode = stdin_inherit_mode
		local
			mutex_locked: BOOLEAN
		do
			command_mutex.lock
			mutex_locked := True
			if not can_start_unlocked then
				raise_client_failure ("Cannot change stdin while a command is running")
			end
			stdin_mode := a_mode
			command_mutex.unlock
			mutex_locked := False
		rescue
			if mutex_locked then
				command_mutex.unlock
			end
		end

	set_stdout_mode (a_mode: INTEGER)
			-- Set the native stdout routing mode.
		require
			valid_mode: a_mode >= output_capture_mode and then a_mode <= output_discard_mode
		local
			mutex_locked: BOOLEAN
		do
			command_mutex.lock
			mutex_locked := True
			if not can_start_unlocked then
				raise_client_failure ("Cannot change stdout while a command is running")
			end
			stdout_mode := a_mode
			command_mutex.unlock
			mutex_locked := False
		rescue
			if mutex_locked then
				command_mutex.unlock
			end
		end

	set_stderr_mode (a_mode: INTEGER)
			-- Set the native stderr routing mode.
		require
			valid_mode: a_mode >= output_capture_mode and then a_mode <= stderr_merge_mode
		local
			mutex_locked: BOOLEAN
		do
			command_mutex.lock
			mutex_locked := True
			if not can_start_unlocked then
				raise_client_failure ("Cannot change stderr while a command is running")
			end
			stderr_mode := a_mode
			command_mutex.unlock
			mutex_locked := False
		rescue
			if mutex_locked then
				command_mutex.unlock
			end
		end

	attached_process: OS_PROCESS
			-- Current execution process.
		local
			snapshot: detachable OS_PROCESS
		do
			command_mutex.lock
			snapshot := current_process
			command_mutex.unlock
			check
				attached snapshot as process
			then
				Result := process
			end
		end

	latest_execution_result: OS_PROCESS_EXECUTION_RESULT
			-- Terminal result used by Current's result queries.
		require
			finished: finished
		do
			Result := attached_process.execution_result
		end

	can_start_unlocked: BOOLEAN
			-- `can_start` while `command_mutex` is held.
		do
			Result := not has_started_state or else (attached current_process as process and then process.is_finished)
		end

	effective_working_directory_unlocked: PATH
			-- Absolute working directory used for lookup while `command_mutex` is held.
		do
			if attached working_directory as directory then
				create Result.make_from_string (directory)
			else
				Result := {EXECUTION_ENVIRONMENT}.current_working_path
			end
		ensure
			absolute: Result.is_absolute
		end

feature {NONE} -- Error reporting

	raise_client_failure (a_message: READABLE_STRING_8)
			-- Report a violated runtime lifecycle obligation.
		do
			(create {EXCEPTIONS}).raise (a_message)
		end

feature {NONE} -- Shell implementation

	shell_executable: STRING_32
			-- Executable for the platform command shell.
		local
			execution_environment: EXECUTION_ENVIRONMENT
			system_shell: PATH
		do
			if {PLATFORM}.is_windows then
				create execution_environment
				if attached execution_environment.item ("COMSPEC") as command_processor and then not command_processor.is_empty then
					Result := command_processor.to_string_32
				elseif attached execution_environment.item ("SystemRoot") as root and then not root.is_empty then
					create system_shell.make_from_string (root)
					Result := system_shell.extended ("System32").extended ("cmd.exe").canonical_path.name.to_string_32
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

	stdin_mode: INTEGER
			-- Native stdin routing mode.

	stdout_mode: INTEGER
			-- Native stdout routing mode.

	stderr_mode: INTEGER
			-- Native stderr routing mode.

	stdin_pipe_mode: INTEGER = 0

	stdin_inherit_mode: INTEGER = 1

	output_capture_mode: INTEGER = 0

	output_inherit_mode: INTEGER = 1

	output_discard_mode: INTEGER = 2

	stderr_merge_mode: INTEGER = 3
			-- Values shared with the constants in `subprocess.h`.

	timeout_milliseconds: INTEGER
			-- Overall execution deadline, or zero when unlimited.

	environment: OS_ENVIRONMENT
			-- Owned variable snapshot and executable resolver.

	command_mutex: MUTEX
			-- Lock protecting configuration and current execution publication.

	current_process: detachable OS_PROCESS
			-- Process owned by the latest execution.

	has_started_state: BOOLEAN
			-- Has at least one execution been started?

invariant

	executable_not_empty: not executable.is_empty
	not_started_has_no_process: not has_started_state implies current_process = Void
	started_has_process: has_started_state implies attached current_process

end
