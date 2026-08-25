class
    OS_PROCESS_HANDLE

create {OS_PROCESS_RUNNER}
    make

feature {NONE} -- Initialization

    make (
        a_executable: READABLE_STRING_GENERAL;
        a_arguments: ITERABLE [READABLE_STRING_GENERAL];
        a_stdout: detachable PROCEDURE [READABLE_STRING_8];
        a_stderr: detachable PROCEDURE [READABLE_STRING_8]
    )
            -- Launch an EiffelStudio `PROCESS`.
        local
            factory: PROCESS_FACTORY
            executable: READABLE_STRING_GENERAL
        do
            create stdout_buffer.make_empty
            create stderr_buffer.make_empty
            stdout_handler := a_stdout
            stderr_handler := a_stderr
            exit_code := -1
            create factory
            executable := resolved_executable (a_executable)
            if {PLATFORM}.is_windows then
                implementation := factory.process_launcher_with_command_line (
                    windows_command_line (executable, a_arguments), Void
                )
            else
                implementation := factory.process_launcher (executable, a_arguments, Void)
            end
            implementation.redirect_output_to_agent (agent receive_stdout)
            implementation.redirect_error_to_agent (agent receive_stderr)
            implementation.launch
            if not implementation.launched then
                exit_code := command_launch_failure
                finished := True
            end
        end

feature {NONE} -- Executable lookup

    resolved_executable (a_executable: READABLE_STRING_GENERAL): STRING_32
            -- `a_executable` resolved through PATH where ISE Unix requires a path.
        local
            environment: EXECUTION_ENVIRONMENT
            platform_environment: OPERATING_ENVIRONMENT
            directories: LIST [STRING_32]
            candidate: STRING_32
            candidate_file: RAW_FILE
            found: BOOLEAN
        do
            Result := a_executable.to_string_32
            if not {PLATFORM}.is_windows and then not Result.has ('/') then
                create environment
                if attached environment.item ("PATH") as path_value then
                    directories := path_value.split (':')
                    create platform_environment
                    from
                        directories.start
                    until
                        directories.after or found
                    loop
                        create candidate.make (directories.item.count + Result.count + 1)
                        if directories.item.is_empty then
                            candidate.append_character ('.')
                        else
                            candidate.append (directories.item)
                        end
                        candidate.append_character (platform_environment.directory_separator)
                        candidate.append (Result)
                        create candidate_file.make_with_name (candidate)
                        if
                            candidate_file.exists and then
                            candidate_file.is_plain and then
                            candidate_file.is_access_executable
                        then
                            Result := candidate
                            found := True
                        end
                        directories.forth
                    end
                end
            end
        end

feature {NONE} -- Windows arguments

    windows_command_line (
        a_executable: READABLE_STRING_GENERAL;
        a_arguments: ITERABLE [READABLE_STRING_GENERAL]
    ): STRING_32
            -- Windows command line preserving every argument as one `argv` item.
        do
            create Result.make (a_executable.count)
            append_windows_argument (Result, a_executable)
            across a_arguments as argument loop
                Result.append_character (' ')
                append_windows_argument (Result, argument)
            end
        ensure
            not_empty: not Result.is_empty
        end

    append_windows_argument (a_command_line: STRING_32; a_argument: READABLE_STRING_GENERAL)
            -- Append `a_argument` using Microsoft C runtime parsing rules.
        local
            argument: STRING_32
            character: CHARACTER_32
            index: INTEGER
            backslash_count: INTEGER
            quoted: BOOLEAN
        do
            argument := a_argument.to_string_32
            quoted := argument.is_empty or else
                argument.has (' ') or else
                argument.has ('%T') or else
                argument.has ('%"')
            if quoted then
                a_command_line.append_character ('%"')
                from
                    index := 1
                until
                    index > argument.count
                loop
                    character := argument.item (index)
                    if character = '\' then
                        backslash_count := backslash_count + 1
                    elseif character = '%"' then
                        append_backslashes (a_command_line, backslash_count * 2 + 1)
                        a_command_line.append_character (character)
                        backslash_count := 0
                    else
                        append_backslashes (a_command_line, backslash_count)
                        backslash_count := 0
                        a_command_line.append_character (character)
                    end
                    index := index + 1
                end
                append_backslashes (a_command_line, backslash_count * 2)
                a_command_line.append_character ('%"')
            else
                a_command_line.append (argument)
            end
        end

    append_backslashes (a_command_line: STRING_32; a_count: INTEGER)
            -- Append `a_count` backslashes to `a_command_line`.
        require
            non_negative_count: a_count >= 0
        local
            index: INTEGER
        do
            from
                index := 1
            until
                index > a_count
            loop
                a_command_line.append_character ('\')
                index := index + 1
            end
        end

feature -- Access

    exit_code: INTEGER
            -- Child exit code; -1 while running.

    stdout: STRING_8
            -- Captured standard-output bytes.
        do
            Result := stdout_buffer.to_string_8
        end

    stderr: STRING_8
            -- Captured standard-error bytes.
        do
            Result := stderr_buffer.to_string_8
        end

feature -- Status report

    is_finished: BOOLEAN
            -- Has the child completed?
        do
            Result := finished or else implementation.has_exited
        end

feature -- Basic operations

    wait
            -- Wait for the child and all output callbacks.
        do
            if not finished then
                implementation.wait_for_exit
                exit_code := implementation.exit_code
                finished := True
            end
            if stdout_callback_failed or stderr_callback_failed then
                raise_callback_failure
            end
        ensure
            finished: is_finished
        end

    terminate
            -- Request platform-dependent child termination.
        do
            if not is_finished then
                implementation.terminate
            end
        end

feature {NONE} -- Callback handling

    receive_stdout (a_chunk: READABLE_STRING_8)
            -- Capture and forward one standard-output chunk.
        do
            if not a_chunk.is_empty then
                stdout_buffer.append (a_chunk)
                if attached stdout_handler as handler then
                    handler.call ([a_chunk])
                end
            end
        rescue
            stdout_callback_failed := True
        end

    receive_stderr (a_chunk: READABLE_STRING_8)
            -- Capture and forward one standard-error chunk.
        do
            if not a_chunk.is_empty then
                stderr_buffer.append (a_chunk)
                if attached stderr_handler as handler then
                    handler.call ([a_chunk])
                end
            end
        rescue
            stderr_callback_failed := True
        end

    raise_callback_failure
            -- Report a callback failure after both streams are drained.
        do
            (create {EXCEPTIONS}).raise ("A process output callback failed")
        end

feature {NONE} -- Implementation

    implementation: PROCESS

    stdout_buffer: STRING_8

    stderr_buffer: STRING_8

    stdout_handler: detachable PROCEDURE [READABLE_STRING_8]

    stderr_handler: detachable PROCEDURE [READABLE_STRING_8]

    stdout_callback_failed: BOOLEAN

    stderr_callback_failed: BOOLEAN

    finished: BOOLEAN

    command_launch_failure: INTEGER = 127

end
