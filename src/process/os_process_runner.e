class
    OS_PROCESS_RUNNER

feature -- Basic operations

    shell (a_command: READABLE_STRING_GENERAL): OS_PROCESS_RESULT
            -- Run `a_command` through the platform command shell and capture its output.
        require
            command_not_empty: not a_command.is_empty
        do
            Result := run (shell_executable, shell_arguments (a_command))
        end

    run (
        a_executable: READABLE_STRING_GENERAL;
        a_arguments: ITERABLE [READABLE_STRING_GENERAL]
    ): OS_PROCESS_RESULT
            -- Run `a_executable` with `a_arguments` and capture its output.
        require
            executable_not_empty: not a_executable.is_empty
        local
            process: OS_PROCESS_HANDLE
        do
            process := start (a_executable, a_arguments, Void, Void)
            process.wait
            create Result.make (process.exit_code, process.stdout, process.stderr)
        end

    start (
        a_executable: READABLE_STRING_GENERAL;
        a_arguments: ITERABLE [READABLE_STRING_GENERAL];
        a_stdout: detachable PROCEDURE [READABLE_STRING_8];
        a_stderr: detachable PROCEDURE [READABLE_STRING_8]
    ): OS_PROCESS_HANDLE
            -- Start `a_executable` with `a_arguments` without using a shell.
        require
            executable_not_empty: not a_executable.is_empty
        do
            create Result.make (a_executable, a_arguments, a_stdout, a_stderr)
        end

feature {NONE} -- Shell implementation

    shell_executable: STRING_32
            -- Executable for the platform command shell.
        local
            environment: EXECUTION_ENVIRONMENT
        do
            if {PLATFORM}.is_windows then
                create environment
                if attached environment.item ("COMSPEC") as command_processor and then not command_processor.is_empty then
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

end
