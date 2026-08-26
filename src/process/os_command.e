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
        local
            argument_copy: STRING_32
        do
            create executable.make_from_string_general (a_executable)
            create arguments.make (8)
            across a_arguments as argument loop
                create argument_copy.make_from_string_general (argument)
                arguments.extend (argument_copy)
            end
        ensure
            executable_set: executable.same_string_general (a_executable)
        end

    make_shell (a_command: READABLE_STRING_GENERAL)
            -- Describe execution of `a_command` by the platform shell.
        require
            command_not_empty: not a_command.is_empty
        do
            make (shell_executable, shell_arguments (a_command))
        end

feature -- Execution

    run: OS_PROCESS_RESULT
            -- Execute synchronously and return the completed outcome.
        local
            process: OS_PROCESS
        do
            process := start
            process.wait
            Result := process.outcome
        end

    start: OS_PROCESS
            -- Start an independent execution without output handlers.
        do
            create Result.make (executable, arguments, Void, Void)
        end

    start_with_handlers (
        a_stdout: detachable PROCEDURE [READABLE_STRING_8];
        a_stderr: detachable PROCEDURE [READABLE_STRING_8]
    ): OS_PROCESS
            -- Start an independent execution and forward output chunks.
        do
            create Result.make (executable, arguments, a_stdout, a_stderr)
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

feature {NONE} -- Implementation

    executable: STRING_32
            -- Copied executable name or path.

    arguments: ARRAYED_LIST [STRING_32]
            -- Copied argument vector.

end
