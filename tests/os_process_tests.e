class
    OS_PROCESS_TESTS

create
    make

feature {NONE} -- Initialization

    make
            -- Run the test suite, or act as a child process for one test.
        local
            arguments: ARGUMENTS_32
        do
            create arguments
            create callback_stdout.make_empty
            create callback_stderr.make_empty
            if arguments.argument_count >= 2 and then arguments.argument (1).same_string_general ("--child") then
                run_child (arguments)
            else
                run_suite (arguments.command_name)
            end
        end

feature {NONE} -- Test suite

    run_suite (a_test_executable: READABLE_STRING_GENERAL)
            -- Exercise the public process API using this executable as the child.
        local
            runner: OS_PROCESS_RUNNER
            exceptions: EXCEPTIONS
        do
            create runner
            create exceptions
            test_arguments (runner, a_test_executable)
            test_nonzero_exit (runner, a_test_executable)
            test_streaming_callbacks (runner, a_test_executable)
            test_large_output (runner, a_test_executable)
            test_wait_is_idempotent (runner, a_test_executable)
            test_path_lookup (runner)
            test_shell (runner)
            test_missing_command (runner)
            test_termination (runner, a_test_executable)

            if failure_count = 0 then
                io.put_string ("All os_process tests passed.%N")
            else
                io.error.put_string ("Failures: ")
                io.error.put_integer (failure_count)
                io.error.put_new_line
                exceptions.die (1)
            end
        end

    test_arguments (a_runner: OS_PROCESS_RUNNER; a_test_executable: READABLE_STRING_GENERAL)
            -- Preserve spaces, quotes, backslashes, and an empty argument.
        local
            process_result: OS_PROCESS_RESULT
            arguments: ARRAYED_LIST [READABLE_STRING_GENERAL]
        do
            create arguments.make (6)
            arguments.extend ("--child")
            arguments.extend ("arguments")
            arguments.extend ("hello world")
            arguments.extend ("a%"b")
            arguments.extend ("c\d")
            arguments.extend ("")
            process_result := a_runner.run (a_test_executable, arguments)
            assert ("arguments exit", process_result.exit_code = 0)
            assert ("arguments stdout", process_result.stdout.same_string ("[11]hello world[3]a%"b[3]c\d[0]"))
            assert ("arguments stderr", process_result.stderr.is_empty)
        end

    test_nonzero_exit (a_runner: OS_PROCESS_RUNNER; a_test_executable: READABLE_STRING_GENERAL)
            -- Return the child's nonzero exit status.
        local
            process_result: OS_PROCESS_RESULT
        do
            process_result := a_runner.run (a_test_executable, child_arguments ("exit-seven"))
            assert ("nonzero exit", process_result.exit_code = 7)
            assert ("nonzero successful", not process_result.successful)
        end

    test_streaming_callbacks (a_runner: OS_PROCESS_RUNNER; a_test_executable: READABLE_STRING_GENERAL)
            -- Capture each stream and forward the same bytes to its callback.
        local
            process: OS_PROCESS_HANDLE
        do
            callback_stdout.wipe_out
            callback_stderr.wipe_out
            process := a_runner.start (
                a_test_executable,
                child_arguments ("emit"),
                agent append_stdout,
                agent append_stderr
            )
            process.wait
            assert ("stream exit", process.exit_code = 0)
            assert ("stream stdout", process.stdout.same_string ("stdout-data%N"))
            assert ("stream stderr", process.stderr.same_string ("stderr-data%N"))
            assert ("stdout callback", callback_stdout.same_string (process.stdout))
            assert ("stderr callback", callback_stderr.same_string (process.stderr))
            assert ("stream finished", process.is_finished)
        end

    test_large_output (a_runner: OS_PROCESS_RUNNER; a_test_executable: READABLE_STRING_GENERAL)
            -- Drain both pipes concurrently when each exceeds kernel pipe capacity.
        local
            process_result: OS_PROCESS_RESULT
        do
            process_result := a_runner.run (a_test_executable, child_arguments ("large"))
            assert ("large exit", process_result.exit_code = 0)
            assert ("large stdout", process_result.stdout.count = large_block_size * large_block_count)
            assert ("large stderr", process_result.stderr.count = large_block_size * large_block_count)
        end

    test_wait_is_idempotent (a_runner: OS_PROCESS_RUNNER; a_test_executable: READABLE_STRING_GENERAL)
            -- Permit clients to wait on a completed handle more than once.
        local
            process: OS_PROCESS_HANDLE
            first_output: STRING_8
        do
            process := a_runner.start (a_test_executable, child_arguments ("emit"), Void, Void)
            process.wait
            first_output := process.stdout
            process.wait
            assert ("second wait exit", process.exit_code = 0)
            assert ("second wait output", process.stdout.same_string (first_output))
        end

    test_missing_command (a_runner: OS_PROCESS_RUNNER)
            -- Represent a missing executable as the conventional launch failure.
        local
            process_result: OS_PROCESS_RESULT
        do
            process_result := a_runner.run (
                "os-process-command-that-must-not-exist-4f27a5b2",
                create {ARRAYED_LIST [READABLE_STRING_GENERAL]}.make (0)
            )
            assert ("missing command", process_result.exit_code = 127)
            assert ("missing stdout", process_result.stdout.is_empty)
            assert ("missing stderr", process_result.stderr.is_empty)
        end

    test_path_lookup (a_runner: OS_PROCESS_RUNNER)
            -- Find a simple executable name through PATH without invoking a shell.
        local
            process_result: OS_PROCESS_RESULT
            arguments: ARRAYED_LIST [READABLE_STRING_GENERAL]
        do
            create arguments.make (1)
            arguments.extend ("--version")
            process_result := a_runner.run ("git", arguments)
            assert ("PATH lookup", process_result.exit_code = 0)
        end

    test_shell (a_runner: OS_PROCESS_RUNNER)
            -- Interpret command chaining and redirection through the platform shell.
        local
            process_result: OS_PROCESS_RESULT
        do
            if {PLATFORM}.is_windows then
                process_result := a_runner.shell (
                    "echo shell-stdout&echo shell-stderr 1>&2&exit /b 9"
                )
            else
                process_result := a_runner.shell (
                    "printf shell-stdout; printf shell-stderr >&2; exit 9"
                )
            end
            assert ("shell exit", process_result.exit_code = 9)
            assert ("shell stdout", process_result.stdout.has_substring ("shell-stdout"))
            assert ("shell stderr", process_result.stderr.has_substring ("shell-stderr"))
        end

    test_termination (a_runner: OS_PROCESS_RUNNER; a_test_executable: READABLE_STRING_GENERAL)
            -- Request termination and still allow normal wait/cleanup.
        local
            process: OS_PROCESS_HANDLE
        do
            process := a_runner.start (a_test_executable, child_arguments ("sleep"), Void, Void)
            process.terminate
            process.wait
            assert ("termination finished", process.is_finished)
        end

feature {NONE} -- Child modes

    run_child (a_arguments: ARGUMENTS_32)
            -- Perform the child behavior selected by argument 2.
        local
            mode: STRING_32
            exceptions: EXCEPTIONS
            environment: EXECUTION_ENVIRONMENT
        do
            create exceptions
            mode := a_arguments.argument (2).to_string_32
            if mode.same_string_general ("arguments") then
                emit_arguments (a_arguments)
            elseif mode.same_string_general ("exit-seven") then
                exceptions.die (7)
            elseif mode.same_string_general ("emit") then
                io.put_string ("stdout-data%N")
                io.error.put_string ("stderr-data%N")
            elseif mode.same_string_general ("large") then
                emit_large_output
            elseif mode.same_string_general ("sleep") then
                create environment
                environment.sleep (10_000_000_000)
            else
                exceptions.die (2)
            end
        end

    emit_arguments (a_arguments: ARGUMENTS_32)
            -- Serialize child arguments without relying on delimiters alone.
        local
            index: INTEGER
            value: STRING_32
        do
            from
                index := 3
            until
                index > a_arguments.argument_count
            loop
                value := a_arguments.argument (index).to_string_32
                io.put_character ('[')
                io.put_integer (value.count)
                io.put_character (']')
                io.put_string (value.to_string_8)
                index := index + 1
            end
        end

    emit_large_output
            -- Write enough bytes to both streams to detect sequential-drain deadlocks.
        local
            stdout_block: STRING_8
            stderr_block: STRING_8
            index: INTEGER
        do
            create stdout_block.make_filled ('o', large_block_size)
            create stderr_block.make_filled ('e', large_block_size)
            from
                index := 1
            until
                index > large_block_count
            loop
                io.put_string (stdout_block)
                io.error.put_string (stderr_block)
                index := index + 1
            end
        end

feature {NONE} -- Callback collection

    append_stdout (a_chunk: READABLE_STRING_8)
            -- Record one stdout callback.
        do
            callback_stdout.append (a_chunk)
        end

    append_stderr (a_chunk: READABLE_STRING_8)
            -- Record one stderr callback.
        do
            callback_stderr.append (a_chunk)
        end

feature {NONE} -- Support

    child_arguments (a_mode: READABLE_STRING_GENERAL): ARRAYED_LIST [READABLE_STRING_GENERAL]
            -- Arguments selecting child `a_mode`.
        do
            create Result.make (2)
            Result.extend ("--child")
            Result.extend (a_mode)
        end

    assert (a_name: READABLE_STRING_8; a_condition: BOOLEAN)
            -- Record whether named test condition `a_condition` holds.
        do
            if a_condition then
                io.put_string ("PASS: ")
                io.put_string (a_name)
                io.put_new_line
            else
                failure_count := failure_count + 1
                io.error.put_string ("FAIL: ")
                io.error.put_string (a_name)
                io.error.put_new_line
            end
        end

feature {NONE} -- State

    callback_stdout: STRING_8

    callback_stderr: STRING_8

    failure_count: INTEGER

    large_block_size: INTEGER = 4096

    large_block_count: INTEGER = 128

end
