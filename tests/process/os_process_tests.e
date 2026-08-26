class
    OS_PROCESS_TESTS

inherit
    TS_TEST_CASE
        redefine
            initialize,
            set_up,
            tear_down
        end

create
    make_default

feature {NONE} -- Initialization

    initialize
            -- Initialize callback buffers for one test case.
        do
            create callback_stdout.make_empty
            create callback_stderr.make_empty
            callback_call_count := 0
        end

feature -- Execution

    set_up
            -- Reserve a unique absent path for one test.
        do
            test_root := new_test_root
        end

    tear_down
            -- Remove the test tree after success or failure.
        do
            cleanup
        end

feature -- Test

    test_arguments
            -- Preserve spaces, quotes, backslashes, and an empty argument.
        local
            command: OS_COMMAND
            process_result: OS_PROCESS_RESULT
            arguments: ARRAYED_LIST [READABLE_STRING_GENERAL]
        do
            create arguments.make (7)
            arguments.extend ("--child")
            arguments.extend ("arguments")
            arguments.extend ("hello world")
            arguments.extend ("a%"b")
            arguments.extend ("c\d")
            arguments.extend ("ends with slash\")
            arguments.extend ("")
            create command.make (process_child_executable, arguments)
            process_result := command.run
            assert_integers_equal ("arguments exit", 0, process_result.exit_code)
            assert_readable_strings_equal (
                "arguments stdout",
                "[11]hello world[3]a%"b[3]c\d[16]ends with slash\[0]",
                process_result.stdout
            )
            assert_true ("arguments stderr", process_result.stderr.is_empty)
        end

    test_nonzero_exit
            -- Return the child's nonzero exit status.
        local
            command: OS_COMMAND
            process_result: OS_PROCESS_RESULT
        do
            create command.make (process_child_executable, child_arguments ("exit-seven"))
            process_result := command.run
            assert_true ("nonzero child launched", process_result.was_launched)
            assert_integers_equal ("nonzero exit", 7, process_result.exit_code)
            assert_false ("nonzero successful", process_result.successful)
        end

    test_child_exit_127
            -- Distinguish a child exit code 127 from a launch failure.
        local
            command: OS_COMMAND
            process_result: OS_PROCESS_RESULT
        do
            create command.make (process_child_executable, child_arguments ("exit-127"))
            process_result := command.run
            assert_true ("exit 127 child launched", process_result.was_launched)
            assert_integers_equal ("exit 127 code", 127, process_result.exit_code)
            assert_false ("exit 127 unsuccessful", process_result.successful)
        end

    test_streaming_callbacks
            -- Capture each stream and forward the same bytes to its callback.
        local
            command: OS_COMMAND
            process: OS_PROCESS
            process_result: OS_PROCESS_RESULT
        do
            callback_stdout.wipe_out
            callback_stderr.wipe_out
            create command.make (process_child_executable, child_arguments ("emit"))
            process := command.start_with_handlers (
                agent append_stdout,
                agent append_stderr
            )
            process.wait
            process_result := process.outcome
            assert_integers_equal ("stream exit", 0, process_result.exit_code)
            assert_readable_strings_equal ("stream stdout", "stdout-data", process_result.stdout)
            assert_readable_strings_equal ("stream stderr", "stderr-data", process_result.stderr)
            assert_readable_strings_equal ("stdout callback", process_result.stdout, callback_stdout)
            assert_readable_strings_equal ("stderr callback", process_result.stderr, callback_stderr)
            assert_true ("stream finished", process.is_finished)
        end

    test_callback_failure
            -- Contain one callback exception and report it after cleanup.
        local
            command: OS_COMMAND
            process: OS_PROCESS
        do
            callback_call_count := 0
            create command.make (process_child_executable, child_arguments ("large"))
            process := command.start_with_handlers (agent fail_stdout, Void)

            assert_true ("callback wait failed", wait_failed (process))
            assert_true ("callback process finished", process.is_finished)
            assert_integers_equal ("callback disabled after failure", 1, callback_call_count)
            assert_true ("callback outcome failed", outcome_failed (process))
        end

    test_polled_callback_failure
            -- Report the same callback failure through nonblocking polling.
        local
            command: OS_COMMAND
            process: OS_PROCESS
        do
            callback_call_count := 0
            create command.make (process_child_executable, child_arguments ("large"))
            process := command.start_with_handlers (agent fail_stdout, Void)

            assert_true ("callback poll failed", polling_failed (process))
            assert_true ("polled callback process finished", process.is_finished)
            assert_integers_equal ("polled callback disabled", 1, callback_call_count)
            assert_true ("polled callback outcome failed", outcome_failed (process))
        end

    test_large_output
            -- Drain both pipes concurrently when each exceeds kernel pipe capacity.
        local
            command: OS_COMMAND
            process_result: OS_PROCESS_RESULT
        do
            create command.make (process_child_executable, child_arguments ("large"))
            process_result := command.run
            assert_integers_equal ("large exit", 0, process_result.exit_code)
            assert_integers_equal ("large stdout", large_block_size * large_block_count, process_result.stdout.count)
            assert_integers_equal ("large stderr", large_block_size * large_block_count, process_result.stderr.count)
        end

    test_default_input_is_eof
            -- Close standard input immediately when no bytes are configured.
        local
            command: OS_COMMAND
            process_result: OS_PROCESS_RESULT
        do
            create command.make (process_child_executable, child_arguments ("count-input"))
            process_result := command.run
            assert_integers_equal ("default input exit", 0, process_result.exit_code)
            assert_readable_strings_equal ("default input count", "0", process_result.stdout)
        end

    test_input_bytes_and_caller_snapshot
            -- Preserve all STRING_8 bytes and do not retain the caller's string.
        local
            command: OS_COMMAND
            process_result: OS_PROCESS_RESULT
            bytes: STRING_8
        do
            create bytes.make_from_string ("before")
            bytes.append_character ('%U')
            bytes.append_code (255)
            create command.make (process_child_executable, child_arguments ("input-codes"))
            command.set_input (bytes)
            bytes.wipe_out

            process_result := command.run
            assert_integers_equal ("byte input exit", 0, process_result.exit_code)
            assert_readable_strings_equal (
                "byte input",
                "8:98,101,102,111,114,101,0,255",
                process_result.stdout
            )
        end

    test_input_snapshot_for_overlapping_starts
            -- Give each start the input configured at that start.
        local
            command: OS_COMMAND
            first_process: OS_PROCESS
            second_process: OS_PROCESS
        do
            create command.make (process_child_executable, child_arguments ("echo-input"))
            command.set_input ("first input")
            first_process := command.start
            command.set_input ("second input")
            second_process := command.start
            first_process.wait
            second_process.wait

            assert_readable_strings_equal ("first input snapshot", "first input", first_process.outcome.stdout)
            assert_readable_strings_equal ("second input snapshot", "second input", second_process.outcome.stdout)
        end

    test_large_duplex_input_and_output
            -- Avoid deadlock when all three standard pipes exceed kernel capacity.
        local
            command: OS_COMMAND
            process_result: OS_PROCESS_RESULT
            bytes: STRING_8
            output_byte_count: INTEGER
        do
            create bytes.make_filled ('i', large_block_size * large_block_count)
            create command.make (process_child_executable, child_arguments ("duplex"))
            command.set_input (bytes)
            process_result := command.run
            output_byte_count := large_block_size * large_block_count

            assert_integers_equal ("duplex exit", 0, process_result.exit_code)
            assert_integers_equal (
                "duplex stdout count",
                output_byte_count + bytes.count.out.count,
                process_result.stdout.count
            )
            assert_readable_strings_equal (
                "duplex input count",
                bytes.count.out,
                process_result.stdout.substring (output_byte_count + 1, process_result.stdout.count)
            )
            assert_integers_equal ("duplex stderr count", output_byte_count, process_result.stderr.count)
        end

    test_early_input_close
            -- Treat child exit during a large write as a normal broken pipe.
        local
            command: OS_COMMAND
            process_result: OS_PROCESS_RESULT
            bytes: STRING_8
        do
            create bytes.make_filled ('i', large_block_size * large_block_count)
            create command.make (process_child_executable, child_arguments ("close-input"))
            command.set_input (bytes)
            process_result := command.run
            assert_integers_equal ("early close exit", 0, process_result.exit_code)
        end

    test_shell_input
            -- Feed configured input through a command created with `make_shell`.
        local
            command: OS_COMMAND
            process_result: OS_PROCESS_RESULT
        do
            if {PLATFORM}.is_windows then
                create command.make_shell ("findstr .")
                command.set_input ("shell-input%R%N")
            else
                create command.make_shell ("cat")
                command.set_input ("shell-input")
            end
            process_result := command.run
            assert_integers_equal ("shell input exit", 0, process_result.exit_code)
            assert_true ("shell input", process_result.stdout.has_substring ("shell-input"))
        end

    test_wait_is_idempotent
            -- Permit clients to wait on a completed process more than once.
        local
            command: OS_COMMAND
            process: OS_PROCESS
            first_output: READABLE_STRING_8
        do
            create command.make (process_child_executable, child_arguments ("emit"))
            process := command.start
            process.wait
            first_output := process.outcome.stdout
            process.wait
            assert_integers_equal ("second wait exit", 0, process.outcome.exit_code)
            assert_readable_strings_equal ("second wait output", first_output, process.outcome.stdout)
        end

    test_missing_command
            -- Represent a missing executable as the conventional launch failure.
        local
            command: OS_COMMAND
            process_result: OS_PROCESS_RESULT
        do
            create command.make (
                "os-process-command-that-must-not-exist-4f27a5b2",
                create {ARRAYED_LIST [READABLE_STRING_GENERAL]}.make (0)
            )
            process_result := command.run
            assert_false ("missing command not launched", process_result.was_launched)
            assert_integers_equal ("missing command", 127, process_result.exit_code)
            assert_true ("missing stdout", process_result.stdout.is_empty)
            assert_true ("missing stderr", process_result.stderr.is_empty)
        end

    test_missing_working_directory
            -- Represent an unavailable working directory as a launch failure.
        local
            command: OS_COMMAND
            process_result: OS_PROCESS_RESULT
        do
            create command.make (
                process_child_executable,
                child_arguments ("working-directory")
            )
            command.set_working_directory (current_test_root.name)
            process_result := command.run
            assert_false ("missing directory not launched", process_result.was_launched)
            assert_integers_equal ("missing working directory", 127, process_result.exit_code)
            assert_true ("missing directory stdout", process_result.stdout.is_empty)
            assert_true ("missing directory stderr", process_result.stderr.is_empty)
        end

    test_path_lookup
            -- Find a simple executable name through PATH without invoking a shell.
        local
            command: OS_COMMAND
            process_result: OS_PROCESS_RESULT
            arguments: ARRAYED_LIST [READABLE_STRING_GENERAL]
        do
            create arguments.make (1)
            arguments.extend ("--version")
            create command.make ("git", arguments)
            process_result := command.run
            assert_integers_equal ("PATH lookup", 0, process_result.exit_code)
        end

    test_shell
            -- Interpret command chaining and redirection through the platform shell.
        local
            command: OS_COMMAND
            process_result: OS_PROCESS_RESULT
        do
            if {PLATFORM}.is_windows then
                create command.make_shell (
                    "echo shell-stdout&echo shell-stderr 1>&2&exit /b 9"
                )
            else
                create command.make_shell (
                    "printf shell-stdout; printf shell-stderr >&2; exit 9"
                )
            end
            process_result := command.run
            assert_integers_equal ("shell exit", 9, process_result.exit_code)
            assert_true ("shell stdout", process_result.stdout.has_substring ("shell-stdout"))
            assert_true ("shell stderr", process_result.stderr.has_substring ("shell-stderr"))
        end

    test_termination
            -- Request termination and still allow normal wait/cleanup.
        local
            command: OS_COMMAND
            process: OS_PROCESS
            bytes: STRING_8
        do
            create bytes.make_filled ('i', large_block_size * large_block_count)
            create command.make (process_child_executable, child_arguments ("sleep"))
            command.set_input (bytes)
            process := command.start
            process.terminate
            process.wait
            assert_true ("termination finished", process.is_finished)
        end

    test_command_copies_inputs
            -- Keep a private snapshot of the executable and argument data.
        local
            command: OS_COMMAND
            process_result: OS_PROCESS_RESULT
            arguments: ARRAYED_LIST [READABLE_STRING_GENERAL]
            mutable_executable: STRING_32
            mutable_argument: STRING_32
        do
            create mutable_executable.make_from_string_general (process_child_executable)
            create mutable_argument.make_from_string_general ("before")
            create arguments.make (3)
            arguments.extend ("--child")
            arguments.extend ("arguments")
            arguments.extend (mutable_argument)
            create command.make (mutable_executable, arguments)

            mutable_executable.wipe_out
            mutable_argument.replace_substring_all ("before", "after")
            arguments.wipe_out

            process_result := command.run
            assert_integers_equal ("copied arguments exit", 0, process_result.exit_code)
            assert_readable_strings_equal ("copied arguments stdout", "[6]before", process_result.stdout)
        end

    test_repeated_command
            -- Run one command object more than once.
        local
            command: OS_COMMAND
            first_result: OS_PROCESS_RESULT
            second_result: OS_PROCESS_RESULT
        do
            create command.make (process_child_executable, child_arguments ("emit"))
            first_result := command.run
            second_result := command.run
            assert_readable_strings_equal ("first repeated output", "stdout-data", first_result.stdout)
            assert_readable_strings_equal ("second repeated output", first_result.stdout, second_result.stdout)
        end

    test_run_matches_started_outcome
            -- Return the same outcome through synchronous and asynchronous execution.
        local
            command: OS_COMMAND
            process: OS_PROCESS
            run_result: OS_PROCESS_RESULT
            started_result: OS_PROCESS_RESULT
        do
            create command.make (process_child_executable, child_arguments ("emit"))
            run_result := command.run
            process := command.start
            process.wait
            started_result := process.outcome
            assert_integers_equal ("matching exit", run_result.exit_code, started_result.exit_code)
            assert_readable_strings_equal ("matching stdout", run_result.stdout, started_result.stdout)
            assert_readable_strings_equal ("matching stderr", run_result.stderr, started_result.stderr)
        end

    test_overlapping_command_starts
            -- Keep overlapping executions of one command independent.
        local
            command: OS_COMMAND
            first_process: OS_PROCESS
            second_process: OS_PROCESS
        do
            create command.make (process_child_executable, child_arguments ("emit"))
            first_process := command.start
            second_process := command.start
            first_process.wait
            second_process.wait
            assert_readable_strings_equal ("first overlapping output", "stdout-data", first_process.outcome.stdout)
            assert_readable_strings_equal ("second overlapping output", "stdout-data", second_process.outcome.stdout)
        end

    test_inherited_working_directory
            -- Inherit the parent working directory when none is configured.
        local
            command: OS_COMMAND
            process_result: OS_PROCESS_RESULT
            environment: EXECUTION_ENVIRONMENT
        do
            create environment
            create command.make (
                process_child_executable,
                child_arguments ("working-directory")
            )
            process_result := command.run
            assert_readable_strings_equal (
                "inherited working directory",
                utf_8 (environment.current_working_path.name),
                process_result.stdout
            )
        end

    test_working_directory_snapshot
            -- Apply later directory changes only to subsequent executions.
        local
            command: OS_COMMAND
            process: OS_PROCESS
            first_result: OS_PROCESS_RESULT
            second_result: OS_PROCESS_RESULT
            first_directory: PATH
            second_directory: PATH
        do
            first_directory := current_test_root.extended ("first directory")
            second_directory := current_test_root.extended ("second directory")
            create_directory (first_directory)
            create_directory (second_directory)
            create command.make (
                process_child_executable,
                child_arguments ("working-directory")
            )

            command.set_working_directory (first_directory.name)
            process := command.start
            command.set_working_directory (second_directory.name)
            process.wait
            first_result := process.outcome
            second_result := command.run

            assert_readable_strings_equal (
                "started working directory",
                utf_8 (first_directory.canonical_path.name),
                first_result.stdout
            )
            assert_readable_strings_equal (
                "updated working directory",
                utf_8 (second_directory.canonical_path.name),
                second_result.stdout
            )
        end

    test_relative_working_directory_snapshot
            -- Resolve a relative directory when it is configured, not when launched.
        local
            command: OS_COMMAND
            process: OS_PROCESS
            relative_directory: STRING_32
            environment: detachable EXECUTION_ENVIRONMENT
            original_directory: detachable PATH
            parent_changed: BOOLEAN
        do
            create_directory (current_test_root)
            create environment
            original_directory := environment.current_working_path
            create relative_directory.make_from_string_general (".")
            create command.make (
                process_child_executable,
                child_arguments ("working-directory")
            )
            command.set_working_directory (relative_directory)
            relative_directory.append ("-changed")

            environment.change_working_path (current_test_root)
            parent_changed := environment.return_code = 0
            assert_true ("parent directory changed", parent_changed)
            process := command.start
            if attached original_directory as original then
                environment.change_working_path (original)
                parent_changed := environment.return_code /= 0
                assert_false ("parent directory restored", parent_changed)
                process.wait
                assert_readable_strings_equal (
                    "relative directory snapshot",
                    utf_8 (original.canonical_path.name),
                    process.outcome.stdout
                )
            else
                assert_true ("original directory attached", False)
            end
        rescue
            if
                parent_changed and then
                attached environment as saved_environment and then
                attached original_directory as saved_directory
            then
                saved_environment.change_working_path (saved_directory)
            end
        end

    test_polled_result
            -- Make the complete result available through polling alone.
        local
            command: OS_COMMAND
            process: OS_PROCESS
            environment: EXECUTION_ENVIRONMENT
            attempts: INTEGER
        do
            create command.make (process_child_executable, child_arguments ("emit"))
            process := command.start
            create environment
            from
                process.poll
            until
                process.is_finished or attempts = polling_attempt_limit
            loop
                environment.sleep (polling_interval)
                attempts := attempts + 1
                process.poll
            end
            if process.is_finished then
                assert_integers_equal ("polled exit", 0, process.outcome.exit_code)
                assert_readable_strings_equal ("polled stdout", "stdout-data", process.outcome.stdout)
                assert_readable_strings_equal ("polled stderr", "stderr-data", process.outcome.stderr)
            else
                process.terminate
                process.wait
                assert_true ("polling completed", False)
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

    fail_stdout (a_chunk: READABLE_STRING_8)
            -- Fail the first attempted stdout callback.
        do
            callback_call_count := callback_call_count + 1
            (create {EXCEPTIONS}).raise ("Expected callback failure")
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

    wait_failed (a_process: OS_PROCESS): BOOLEAN
            -- Did waiting for `a_process` report a failure?
        local
            retried: BOOLEAN
        do
            if retried then
                Result := True
            else
                a_process.wait
            end
        rescue
            retried := True
            retry
        end

    outcome_failed (a_process: OS_PROCESS): BOOLEAN
            -- Did obtaining `a_process.outcome` report a failure?
        local
            retried: BOOLEAN
            ignored: detachable OS_PROCESS_RESULT
        do
            if retried then
                Result := True
            else
                ignored := a_process.outcome
            end
        rescue
            retried := True
            retry
        end

    polling_failed (a_process: OS_PROCESS): BOOLEAN
            -- Did polling `a_process` to completion report a failure?
        local
            environment: EXECUTION_ENVIRONMENT
            attempts: INTEGER
            retried: BOOLEAN
        do
            if retried then
                Result := True
            else
                create environment
                from
                    a_process.poll
                until
                    a_process.is_finished or attempts = polling_attempt_limit
                loop
                    environment.sleep (polling_interval)
                    attempts := attempts + 1
                    a_process.poll
                end
                if not a_process.is_finished then
                    a_process.terminate
                    a_process.wait
                end
            end
        rescue
            retried := True
            retry
        end

    current_test_root: PATH
            -- Root reserved for the current test.
        require
            test_root_attached: attached test_root
        do
            check attached test_root as root then
                Result := root
            end
        end

    new_test_root: PATH
            -- Unique absent path reserved for this test run.
        local
            environment: EXECUTION_ENVIRONMENT
            temporary_file: PLAIN_TEXT_FILE
            prefix: IMMUTABLE_STRING_32
        do
            create environment
            prefix := environment.current_working_path.extended ("os-process-tests-").name
            create temporary_file.make_open_temporary_with_prefix (prefix)
            Result := temporary_file.path
            temporary_file.close
            temporary_file.delete
        ensure
            absent: not path_exists (Result)
        end

    create_directory (a_path: PATH)
            -- Create `a_path`, including missing parents.
        local
            directory: DIRECTORY
        do
            create directory.make_with_path (a_path)
            directory.recursive_create_dir
        ensure
            exists: path_exists (a_path)
        end

    path_exists (a_path: PATH): BOOLEAN
            -- Does `a_path` denote an existing file-system entry?
        local
            file_info: FILE_INFO
        do
            create file_info.make
            file_info.update (a_path.name)
            Result := file_info.exists
        end

    cleanup
            -- Remove the test tree if one has been reserved.
        local
            directory: DIRECTORY
        do
            if attached test_root as root then
                create directory.make_with_path (root)
                if directory.exists then
                    directory.recursive_delete
                end
                test_root := Void
            end
        ensure
            test_root_detached: test_root = Void
        end

    utf_8 (a_text: READABLE_STRING_GENERAL): STRING_8
            -- UTF-8 representation of `a_text`.
        do
            Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text)
        end

    assert_readable_strings_equal (
        a_tag: STRING_8;
        a_expected, a_actual: READABLE_STRING_8
    )
            -- Assert that `a_actual` has the same bytes as `a_expected`.
        do
            assert_true (a_tag, a_actual.same_string (a_expected))
        end

feature {NONE} -- State

    callback_stdout: STRING_8

    callback_stderr: STRING_8

    callback_call_count: INTEGER

    test_root: detachable PATH

feature {NONE} -- Constants

    process_child_variable: STRING = "process_child"

    large_block_size: INTEGER = 4096

    large_block_count: INTEGER = 128

    polling_attempt_limit: INTEGER = 5_000

    polling_interval: INTEGER_64 = 1_000_000

end
