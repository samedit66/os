class
    OS_PROCESS_TESTS

inherit
    TS_TEST_CASE
        redefine
            initialize
        end

create
    make_default

feature {NONE} -- Initialization

    initialize
            -- Initialize callback buffers for one test case.
        do
            create callback_stdout.make_empty
            create callback_stderr.make_empty
        end

feature -- Test

    test_arguments
            -- Preserve spaces, quotes, backslashes, and an empty argument.
        local
            runner: OS_PROCESS_RUNNER
            process_result: OS_PROCESS_RESULT
            arguments: ARRAYED_LIST [READABLE_STRING_GENERAL]
        do
            create runner
            create arguments.make (6)
            arguments.extend ("--child")
            arguments.extend ("arguments")
            arguments.extend ("hello world")
            arguments.extend ("a%"b")
            arguments.extend ("c\d")
            arguments.extend ("")
            process_result := runner.run (process_child_executable, arguments)
            assert_integers_equal ("arguments exit", 0, process_result.exit_code)
            assert_strings_equal ("arguments stdout", "[11]hello world[3]a%"b[3]c\d[0]", process_result.stdout)
            assert_true ("arguments stderr", process_result.stderr.is_empty)
        end

    test_nonzero_exit
            -- Return the child's nonzero exit status.
        local
            runner: OS_PROCESS_RUNNER
            process_result: OS_PROCESS_RESULT
        do
            create runner
            process_result := runner.run (process_child_executable, child_arguments ("exit-seven"))
            assert_integers_equal ("nonzero exit", 7, process_result.exit_code)
            assert_false ("nonzero successful", process_result.successful)
        end

    test_streaming_callbacks
            -- Capture each stream and forward the same bytes to its callback.
        local
            runner: OS_PROCESS_RUNNER
            process: OS_PROCESS_HANDLE
        do
            callback_stdout.wipe_out
            callback_stderr.wipe_out
            create runner
            process := runner.start (
                process_child_executable,
                child_arguments ("emit"),
                agent append_stdout,
                agent append_stderr
            )
            process.wait
            assert_integers_equal ("stream exit", 0, process.exit_code)
            assert_strings_equal ("stream stdout", "stdout-data", process.stdout)
            assert_strings_equal ("stream stderr", "stderr-data", process.stderr)
            assert_strings_equal ("stdout callback", process.stdout, callback_stdout)
            assert_strings_equal ("stderr callback", process.stderr, callback_stderr)
            assert_true ("stream finished", process.is_finished)
        end

    test_large_output
            -- Drain both pipes concurrently when each exceeds kernel pipe capacity.
        local
            runner: OS_PROCESS_RUNNER
            process_result: OS_PROCESS_RESULT
        do
            create runner
            process_result := runner.run (process_child_executable, child_arguments ("large"))
            assert_integers_equal ("large exit", 0, process_result.exit_code)
            assert_integers_equal ("large stdout", large_block_size * large_block_count, process_result.stdout.count)
            assert_integers_equal ("large stderr", large_block_size * large_block_count, process_result.stderr.count)
        end

    test_wait_is_idempotent
            -- Permit clients to wait on a completed handle more than once.
        local
            runner: OS_PROCESS_RUNNER
            process: OS_PROCESS_HANDLE
            first_output: STRING_8
        do
            create runner
            process := runner.start (process_child_executable, child_arguments ("emit"), Void, Void)
            process.wait
            first_output := process.stdout
            process.wait
            assert_integers_equal ("second wait exit", 0, process.exit_code)
            assert_strings_equal ("second wait output", first_output, process.stdout)
        end

    test_missing_command
            -- Represent a missing executable as the conventional launch failure.
        local
            runner: OS_PROCESS_RUNNER
            process_result: OS_PROCESS_RESULT
        do
            create runner
            process_result := runner.run (
                "os-process-command-that-must-not-exist-4f27a5b2",
                create {ARRAYED_LIST [READABLE_STRING_GENERAL]}.make (0)
            )
            assert_integers_equal ("missing command", 127, process_result.exit_code)
            assert_true ("missing stdout", process_result.stdout.is_empty)
            assert_true ("missing stderr", process_result.stderr.is_empty)
        end

    test_path_lookup
            -- Find a simple executable name through PATH without invoking a shell.
        local
            runner: OS_PROCESS_RUNNER
            process_result: OS_PROCESS_RESULT
            arguments: ARRAYED_LIST [READABLE_STRING_GENERAL]
        do
            create runner
            create arguments.make (1)
            arguments.extend ("--version")
            process_result := runner.run ("git", arguments)
            assert_integers_equal ("PATH lookup", 0, process_result.exit_code)
        end

    test_shell
            -- Interpret command chaining and redirection through the platform shell.
        local
            runner: OS_PROCESS_RUNNER
            process_result: OS_PROCESS_RESULT
        do
            create runner
            if {PLATFORM}.is_windows then
                process_result := runner.shell (
                    "echo shell-stdout&echo shell-stderr 1>&2&exit /b 9"
                )
            else
                process_result := runner.shell (
                    "printf shell-stdout; printf shell-stderr >&2; exit 9"
                )
            end
            assert_integers_equal ("shell exit", 9, process_result.exit_code)
            assert_true ("shell stdout", process_result.stdout.has_substring ("shell-stdout"))
            assert_true ("shell stderr", process_result.stderr.has_substring ("shell-stderr"))
        end

    test_termination
            -- Request termination and still allow normal wait/cleanup.
        local
            runner: OS_PROCESS_RUNNER
            process: OS_PROCESS_HANDLE
        do
            create runner
            process := runner.start (process_child_executable, child_arguments ("sleep"), Void, Void)
            process.terminate
            process.wait
            assert_true ("termination finished", process.is_finished)
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

    process_child_executable: STRING
            -- Path of the helper executable used as a child process.
        do
            if variables.has (process_child_variable) then
                Result := variables.value (process_child_variable)
            else
                assert_true ("process child configured", False)
                create Result.make_empty
            end
        end

    child_arguments (a_mode: READABLE_STRING_GENERAL): ARRAYED_LIST [READABLE_STRING_GENERAL]
            -- Arguments selecting child `a_mode`.
        do
            create Result.make (2)
            Result.extend ("--child")
            Result.extend (a_mode)
        end

feature {NONE} -- State

    callback_stdout: STRING_8

    callback_stderr: STRING_8

feature {NONE} -- Constants

    process_child_variable: STRING = "process_child"

    large_block_size: INTEGER = 4096

    large_block_count: INTEGER = 128

end
