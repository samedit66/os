note

	description:

		"Test cases for process execution, lifecycle, I/O, and failures."

	author: "samedit66 <samedit66@yandex.ru>"
	library: "os"

class OS_PROCESS_TESTS

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
			process_result: OS_PROCESS_EXECUTION_RESULT
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
			command.run
			process_result := command.execution_result
			assert_integers_equal ("arguments exit", 0, process_result.exit_code)
			assert_readable_strings_equal ("arguments stdout", "[11]hello world[3]a%"b[3]c\d[16]ends with slash\[0]", process_result.stdout)
			assert_true ("arguments stderr", process_result.stderr.is_empty)
		end

	test_nonzero_exit
			-- Return the child's nonzero exit status.
		local
			command: OS_COMMAND
			process_result: OS_PROCESS_EXECUTION_RESULT
		do
			create command.make (process_child_executable, child_arguments ("exit-seven"))
			command.run
			process_result := command.execution_result
			assert_true ("nonzero child launched", process_result.was_launched)
			assert_true ("nonzero exit available", process_result.has_exit_code)
			assert_integers_equal ("nonzero exit", 7, process_result.exit_code)
			assert_false ("nonzero successful", process_result.successful)
			assert_false ("nonzero has no library failure", process_result.has_failures)
		end

	test_child_exit_127
			-- Distinguish a child exit code 127 from a launch failure.
		local
			command: OS_COMMAND
			process_result: OS_PROCESS_EXECUTION_RESULT
		do
			create command.make (process_child_executable, child_arguments ("exit-127"))
			command.run
			process_result := command.execution_result
			assert_true ("exit 127 child launched", process_result.was_launched)
			assert_true ("exit 127 available", process_result.has_exit_code)
			assert_integers_equal ("exit 127 code", 127, process_result.exit_code)
			assert_false ("exit 127 unsuccessful", process_result.successful)
			assert_false ("exit 127 has no library failure", process_result.has_failures)
		end

	test_streaming_callbacks
			-- Capture each stream and forward the same bytes to its callback.
		local
			command: OS_COMMAND
			process_result: OS_PROCESS_EXECUTION_RESULT
		do
			callback_stdout.wipe_out
			callback_stderr.wipe_out
			create command.make (process_child_executable, child_arguments ("emit"))
			command.start_streaming (agent append_stdout, agent append_stderr)
			command.wait_for_exit
			process_result := command.execution_result
			assert_integers_equal ("stream exit", 0, process_result.exit_code)
			assert_readable_strings_equal ("stream stdout", "stdout-data", process_result.stdout)
			assert_readable_strings_equal ("stream stderr", "stderr-data", process_result.stderr)
			assert_readable_strings_equal ("stdout callback", process_result.stdout, callback_stdout)
			assert_readable_strings_equal ("stderr callback", process_result.stderr, callback_stderr)
			assert_true ("stream finished", command.finished)
		end

	test_callback_failure
			-- Contain one callback exception and report it after cleanup.
		local
			command: OS_COMMAND
			process_result: OS_PROCESS_EXECUTION_RESULT
		do
			callback_call_count := 0
			create command.make (process_child_executable, child_arguments ("large"))
			command.start_streaming (agent fail_stdout, Void)
			command.wait_for_exit
			process_result := command.execution_result
			assert_true ("callback process finished", command.finished)
			assert_integers_equal ("callback disabled after failure", 1, callback_call_count)
			assert_true ("callback failure recorded", process_result.has_failures)
			assert_true ("stdout handler category", process_result.failures [process_result.failures.lower].kind.is_stdout_handler)
			assert_integers_equal ("callback output retained", large_block_size * large_block_count, process_result.stdout.count)
		end

	test_polled_callback_failure
			-- Report the same callback failure through nonblocking polling.
		local
			command: OS_COMMAND
			environment: EXECUTION_ENVIRONMENT
			attempts: INTEGER
		do
			callback_call_count := 0
			create command.make (process_child_executable, child_arguments ("large"))
			command.start_streaming (agent fail_stdout, Void)
			create environment
			from
				command.poll
			until
				command.finished or attempts = polling_attempt_limit
			loop
				environment.sleep (polling_interval)
				attempts := attempts + 1
				command.poll
			end
			if not command.finished then
				command.terminate
				command.wait_for_exit
			end
			assert_true ("polled callback process finished", command.finished)
			assert_integers_equal ("polled callback disabled", 1, callback_call_count)
			assert_true ("polled callback failure recorded", command.has_failures)
		end

	test_two_callback_failures_are_deterministic
			-- Preserve both concurrent handler failures in stream order.
		local
			command: OS_COMMAND
			failure_snapshot: READABLE_INDEXABLE [OS_PROCESS_FAILURE]
		do
			callback_call_count := 0
			create command.make (process_child_executable, child_arguments ("emit"))
			command.start_streaming (agent fail_stdout, agent fail_stderr)
			command.wait_for_exit
			failure_snapshot := command.execution_result.failures
			assert_integers_equal ("both handlers called once", 2, callback_call_count)
			assert_integers_equal ("two handler failures", 2, indexable_count (failure_snapshot))
			assert_true ("stdout handler ordered first", failure_snapshot [failure_snapshot.lower].kind.is_stdout_handler)
			assert_true ("stderr handler ordered second", failure_snapshot [failure_snapshot.lower + 1].kind.is_stderr_handler)
		end

	test_failure_snapshot_is_defensive
			-- Keep published failures unchanged when a client mutates its snapshot.
		local
			command: OS_COMMAND
			snapshot: READABLE_INDEXABLE [OS_PROCESS_FAILURE]
		do
			create command.make ("os-process-command-that-must-not-exist-4f27a5b2", create {ARRAYED_LIST [READABLE_STRING_GENERAL]}.make (0))
			command.run
			snapshot := command.execution_result.failures
			if attached {ARRAYED_LIST [OS_PROCESS_FAILURE]} snapshot as mutable_snapshot then
				mutable_snapshot.wipe_out
			end
			assert_integers_equal ("result keeps private failures", 1, indexable_count (command.execution_result.failures))
		end

	test_large_output
			-- Drain both pipes concurrently when each exceeds kernel pipe capacity.
		local
			command: OS_COMMAND
			process_result: OS_PROCESS_EXECUTION_RESULT
		do
			create command.make (process_child_executable, child_arguments ("large"))
			command.run
			process_result := command.execution_result
			assert_integers_equal ("large exit", 0, process_result.exit_code)
			assert_integers_equal ("large stdout", large_block_size * large_block_count, process_result.stdout.count)
			assert_integers_equal ("large stderr", large_block_size * large_block_count, process_result.stderr.count)
		end

	test_default_input_is_eof
			-- Close standard input immediately when no bytes are configured.
		local
			command: OS_COMMAND
			process_result: OS_PROCESS_EXECUTION_RESULT
		do
			create command.make (process_child_executable, child_arguments ("count-input"))
			command.run
			process_result := command.execution_result
			assert_integers_equal ("default input exit", 0, process_result.exit_code)
			assert_readable_strings_equal ("default input count", "0", process_result.stdout)
		end

	test_input_bytes_and_caller_snapshot
			-- Preserve all STRING_8 bytes and do not retain the caller's string.
		local
			command: OS_COMMAND
			process_result: OS_PROCESS_EXECUTION_RESULT
			bytes: STRING_8
		do
			create bytes.make_from_string ("before")
			bytes.append_character ('%U')
			bytes.append_code (255)
			create command.make (process_child_executable, child_arguments ("input-codes"))
			command.set_input (bytes)
			bytes.wipe_out
			command.run
			process_result := command.execution_result
			assert_integers_equal ("byte input exit", 0, process_result.exit_code)
			assert_readable_strings_equal ("byte input", "8:98,101,102,111,114,101,0,255", process_result.stdout)
		end

	test_input_snapshot_for_sequential_starts
			-- Give each sequential execution the input configured before its start.
		local
			command: OS_COMMAND
			first_result: OS_PROCESS_EXECUTION_RESULT
			second_result: OS_PROCESS_EXECUTION_RESULT
		do
			create command.make (process_child_executable, child_arguments ("echo-input"))
			command.set_input ("first input")
			command.run
			first_result := command.execution_result
			command.set_input ("second input")
			command.run
			second_result := command.execution_result
			assert_readable_strings_equal ("first input snapshot", "first input", first_result.stdout)
			assert_readable_strings_equal ("second input snapshot", "second input", second_result.stdout)
		end

	test_large_duplex_input_and_output
			-- Avoid deadlock when all three standard pipes exceed kernel capacity.
		local
			command: OS_COMMAND
			process_result: OS_PROCESS_EXECUTION_RESULT
			bytes: STRING_8
			output_byte_count: INTEGER
		do
			create bytes.make_filled ('i', large_block_size * large_block_count)
			create command.make (process_child_executable, child_arguments ("duplex"))
			command.set_input (bytes)
			command.run
			process_result := command.execution_result
			output_byte_count := large_block_size * large_block_count
			assert_integers_equal ("duplex exit", 0, process_result.exit_code)
			assert_integers_equal ("duplex stdout count", output_byte_count + bytes.count.out.count, process_result.stdout.count)
			assert_readable_strings_equal ("duplex input count", bytes.count.out, process_result.stdout.substring (output_byte_count + 1, process_result.stdout.count))
			assert_integers_equal ("duplex stderr count", output_byte_count, process_result.stderr.count)
		end

	test_early_input_close
			-- Treat child exit during a large write as a normal broken pipe.
		local
			command: OS_COMMAND
			process_result: OS_PROCESS_EXECUTION_RESULT
			bytes: STRING_8
		do
			create bytes.make_filled ('i', large_block_size * large_block_count)
			create command.make (process_child_executable, child_arguments ("close-input"))
			command.set_input (bytes)
			command.run
			process_result := command.execution_result
			assert_integers_equal ("early close exit", 0, process_result.exit_code)
		end

	test_shell_input
			-- Feed configured input through a command created with `make_shell`.
		local
			command: OS_COMMAND
			process_result: OS_PROCESS_EXECUTION_RESULT
		do
			if {PLATFORM}.is_windows then
				create command.make_shell ("findstr .")
				command.set_input ("shell-input%R%N")
			else
				create command.make_shell ("cat")
				command.set_input ("shell-input")
			end
			command.run
			process_result := command.execution_result
			assert_integers_equal ("shell input exit", 0, process_result.exit_code)
			assert_true ("shell input", process_result.stdout.has_substring ("shell-input"))
		end

	test_wait_is_idempotent
			-- Permit clients to wait on a completed process more than once.
		local
			command: OS_COMMAND
			first_output: READABLE_STRING_8
		do
			create command.make (process_child_executable, child_arguments ("emit"))
			command.start
			command.wait_for_exit
			first_output := command.execution_result.stdout
			command.wait_for_exit
			assert_integers_equal ("second wait exit", 0, command.execution_result.exit_code)
			assert_readable_strings_equal ("second wait output", first_output, command.execution_result.stdout)
		end

	test_missing_command
			-- Represent a missing executable without a synthetic exit code.
		local
			command: OS_COMMAND
			process_result: OS_PROCESS_EXECUTION_RESULT
		do
			create command.make ("os-process-command-that-must-not-exist-4f27a5b2", create {ARRAYED_LIST [READABLE_STRING_GENERAL]}.make (0))
			command.run
			process_result := command.execution_result
			assert_false ("missing command not launched", process_result.was_launched)
			assert_false ("missing command has no exit", process_result.has_exit_code)
			assert_true ("missing command failure", process_result.has_failures)
			assert_true ("missing command launch category", process_result.failures [process_result.failures.lower].kind.is_launch)
			assert_true ("missing stdout", process_result.stdout.is_empty)
			assert_true ("missing stderr", process_result.stderr.is_empty)
		end

	test_missing_working_directory
			-- Represent an unavailable working directory as a launch failure.
		local
			command: OS_COMMAND
			process_result: OS_PROCESS_EXECUTION_RESULT
		do
			create command.make (process_child_executable, child_arguments ("working-directory"))
			command.set_working_directory (current_test_root.name)
			command.run
			process_result := command.execution_result
			assert_false ("missing directory not launched", process_result.was_launched)
			assert_false ("missing directory has no exit", process_result.has_exit_code)
			assert_true ("missing directory failure", process_result.has_failures)
			assert_true ("missing directory stdout", process_result.stdout.is_empty)
			assert_true ("missing directory stderr", process_result.stderr.is_empty)
		end

	test_path_lookup
			-- Find a simple executable name through PATH without invoking a shell.
		local
			command: OS_COMMAND
			process_result: OS_PROCESS_EXECUTION_RESULT
			arguments: ARRAYED_LIST [READABLE_STRING_GENERAL]
		do
			create arguments.make (1)
			arguments.extend ("--version")
			create command.make ("git", arguments)
			command.run
			process_result := command.execution_result
			assert_integers_equal ("PATH lookup", 0, process_result.exit_code)
		end

	test_shell
			-- Interpret command chaining and redirection through the platform shell.
		local
			command: OS_COMMAND
			process_result: OS_PROCESS_EXECUTION_RESULT
		do
			if {PLATFORM}.is_windows then
				create command.make_shell ("echo shell-stdout&echo shell-stderr 1>&2&exit /b 9")
			else
				create command.make_shell ("printf shell-stdout; printf shell-stderr >&2; exit 9")
			end
			command.run
			process_result := command.execution_result
			assert_integers_equal ("shell exit", 9, process_result.exit_code)
			assert_true ("shell stdout", process_result.stdout.has_substring ("shell-stdout"))
			assert_true ("shell stderr", process_result.stderr.has_substring ("shell-stderr"))
		end

	test_termination
			-- Request termination and still allow normal wait/cleanup.
		local
			command: OS_COMMAND
			bytes: STRING_8
		do
			create bytes.make_filled ('i', large_block_size * large_block_count)
			create command.make (process_child_executable, child_arguments ("sleep"))
			command.set_input (bytes)
			command.start
			command.terminate
			command.wait_for_exit
			assert_true ("termination finished", command.finished)
		end

	test_lifecycle_calls_are_serialized
			-- Serialize concurrent wait and terminate calls on one command.
		local
			command: OS_COMMAND
			waiter: OS_COMMAND_LIFECYCLE_CALLER
			terminator: OS_COMMAND_LIFECYCLE_CALLER
		do
			create command.make (process_child_executable, child_arguments ("short-sleep"))
			command.start
			create waiter.make_wait (command)
			create terminator.make_terminate (command)
			waiter.launch
			terminator.launch
			waiter.join
			terminator.join
			assert_true ("concurrent wait returned", waiter.successful)
			assert_true ("concurrent terminate returned", terminator.successful)
			assert_true ("concurrent lifecycle finished", command.finished)
		end

	test_concurrent_starts_are_atomic
			-- Allow exactly one of two concurrent starts to create a child.
		local
			command: OS_COMMAND
			first_starter: OS_COMMAND_LIFECYCLE_CALLER
			second_starter: OS_COMMAND_LIFECYCLE_CALLER
			successful_starts: INTEGER
		do
			create command.make (process_child_executable, child_arguments ("short-sleep"))
			create first_starter.make_start (command)
			create second_starter.make_start (command)
			first_starter.launch
			second_starter.launch
			first_starter.join
			second_starter.join
			if first_starter.successful then
				successful_starts := successful_starts + 1
			end
			if second_starter.successful then
				successful_starts := successful_starts + 1
			end
			assert_integers_equal ("one concurrent start", 1, successful_starts)
			assert_true ("concurrent start recorded", command.has_started)
			command.wait_for_exit
		end

	test_finished_is_passive
			-- Require polling or waiting to observe native completion.
		local
			command: OS_COMMAND
			environment: EXECUTION_ENVIRONMENT
		do
			create command.make (process_child_executable, child_arguments ("short-sleep"))
			command.start
			create environment
			environment.sleep (200_000_000)
			assert_false ("completion not observed implicitly", command.finished)
			command.poll
			if not command.finished then
				command.wait_for_exit
			end
			assert_true ("completion observed explicitly", command.finished)
		end

	test_nul_command_text_is_rejected
			-- Reject NUL in command text while preserving binary standard input.
		do
			assert_true ("NUL executable rejected", nul_executable_rejected)
			assert_true ("NUL argument rejected", nul_argument_rejected)
			assert_true ("NUL directory rejected", nul_directory_rejected)
			assert_true ("NUL shell command rejected", nul_shell_command_rejected)
		end

	test_command_copies_inputs
			-- Keep a private snapshot of the executable and argument data.
		local
			command: OS_COMMAND
			process_result: OS_PROCESS_EXECUTION_RESULT
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
			command.run
			process_result := command.execution_result
			assert_integers_equal ("copied arguments exit", 0, process_result.exit_code)
			assert_readable_strings_equal ("copied arguments stdout", "[6]before", process_result.stdout)
		end

	test_repeated_command
			-- Run one command object more than once.
		local
			command: OS_COMMAND
			first_result: OS_PROCESS_EXECUTION_RESULT
			second_result: OS_PROCESS_EXECUTION_RESULT
		do
			create command.make (process_child_executable, child_arguments ("emit"))
			command.run
			first_result := command.execution_result
			command.run
			second_result := command.execution_result
			assert_readable_strings_equal ("first repeated output", "stdout-data", first_result.stdout)
			assert_readable_strings_equal ("second repeated output", first_result.stdout, second_result.stdout)
		end

	test_run_matches_started_result
			-- Publish equivalent results through synchronous and asynchronous execution.
		local
			command: OS_COMMAND
			run_result: OS_PROCESS_EXECUTION_RESULT
			started_result: OS_PROCESS_EXECUTION_RESULT
		do
			create command.make (process_child_executable, child_arguments ("emit"))
			command.run
			run_result := command.execution_result
			command.start
			command.wait_for_exit
			started_result := command.execution_result
			assert_integers_equal ("matching exit", run_result.exit_code, started_result.exit_code)
			assert_readable_strings_equal ("matching stdout", run_result.stdout, started_result.stdout)
			assert_readable_strings_equal ("matching stderr", run_result.stderr, started_result.stderr)
		end

	test_overlapping_command_starts_are_forbidden
			-- Forbid a second start until the current execution is terminal.
		local
			command: OS_COMMAND
		do
			create command.make (process_child_executable, child_arguments ("sleep"))
			command.start
			assert_false ("active command cannot start", command.can_start)
			command.terminate
			command.wait_for_exit
			assert_true ("terminal command can start", command.can_start)
		end

	test_inherited_working_directory
			-- Inherit the parent working directory when none is configured.
		local
			command: OS_COMMAND
			process_result: OS_PROCESS_EXECUTION_RESULT
			environment: EXECUTION_ENVIRONMENT
		do
			create environment
			create command.make (process_child_executable, child_arguments ("working-directory"))
			command.run
			process_result := command.execution_result
			assert_readable_strings_equal ("inherited working directory", utf_8 (environment.current_working_path.name), process_result.stdout)
		end

	test_working_directory_snapshot
			-- Apply later directory changes only to subsequent executions.
		local
			command: OS_COMMAND
			first_result: OS_PROCESS_EXECUTION_RESULT
			second_result: OS_PROCESS_EXECUTION_RESULT
			first_directory: PATH
			second_directory: PATH
		do
			first_directory := current_test_root.extended ("first directory")
			second_directory := current_test_root.extended ("second directory")
			create_directory (first_directory)
			create_directory (second_directory)
			create command.make (process_child_executable, child_arguments ("working-directory"))
			command.set_working_directory (first_directory.name)
			command.run
			first_result := command.execution_result
			command.set_working_directory (second_directory.name)
			command.run
			second_result := command.execution_result
			assert_readable_strings_equal ("started working directory", utf_8 (first_directory.canonical_path.name), first_result.stdout)
			assert_readable_strings_equal ("updated working directory", utf_8 (second_directory.canonical_path.name), second_result.stdout)
		end

	test_relative_working_directory_snapshot
			-- Resolve a relative directory when it is configured, not when launched.
		local
			command: OS_COMMAND
			relative_directory: STRING_32
			environment: detachable EXECUTION_ENVIRONMENT
			original_directory: detachable PATH
			parent_changed: BOOLEAN
		do
			create_directory (current_test_root)
			create environment
			original_directory := environment.current_working_path
			create relative_directory.make_from_string_general (".")
			create command.make (process_child_executable, child_arguments ("working-directory"))
			command.set_working_directory (relative_directory)
			relative_directory.append ("-changed")
			environment.change_working_path (current_test_root)
			parent_changed := environment.return_code = 0
			assert_true ("parent directory changed", parent_changed)
			command.start
			if attached original_directory as original then
				environment.change_working_path (original)
				parent_changed := environment.return_code /= 0
				assert_false ("parent directory restored", parent_changed)
				command.wait_for_exit
				assert_readable_strings_equal ("relative directory snapshot", utf_8 (original.canonical_path.name), command.execution_result.stdout)
			else
				assert_true ("original directory attached", False)
			end
		rescue
			if parent_changed and then attached environment as saved_environment and then attached original_directory as saved_directory then
				saved_environment.change_working_path (saved_directory)
			end
		end

	test_polled_result
			-- Make the complete result available through polling alone.
		local
			command: OS_COMMAND
			environment: EXECUTION_ENVIRONMENT
			attempts: INTEGER
		do
			create command.make (process_child_executable, child_arguments ("emit"))
			command.start
			create environment
			from
				command.poll
			until
				command.finished or attempts = polling_attempt_limit
			loop
				environment.sleep (polling_interval)
				attempts := attempts + 1
				command.poll
			end
			if command.finished then
				assert_integers_equal ("polled exit", 0, command.execution_result.exit_code)
				assert_readable_strings_equal ("polled stdout", "stdout-data", command.execution_result.stdout)
				assert_readable_strings_equal ("polled stderr", "stderr-data", command.execution_result.stderr)
			else
				command.terminate
				command.wait_for_exit
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

	fail_stderr (a_chunk: READABLE_STRING_8)
			-- Fail the first attempted stderr callback.
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

	indexable_count (a_items: READABLE_INDEXABLE [OS_PROCESS_FAILURE]): INTEGER
			-- Number of items in `a_items`.
		do
			Result := a_items.upper - a_items.lower + 1
		ensure
			nonnegative: Result >= 0
		end

	nul_executable_rejected: BOOLEAN
			-- Does command creation reject NUL in the executable?
		local
			command: OS_COMMAND
			executable_name: STRING_32
			retried: BOOLEAN
		do
			if retried then
				Result := True
			else
				create executable_name.make_from_string_general ("git")
				executable_name.append_code (0)
				create command.make (executable_name, create {ARRAYED_LIST [READABLE_STRING_GENERAL]}.make (0))
			end
		rescue
			retried := True
			retry
		end

	nul_argument_rejected: BOOLEAN
			-- Does command creation reject NUL in an argument?
		local
			command: OS_COMMAND
			arguments: ARRAYED_LIST [READABLE_STRING_GENERAL]
			argument: STRING_32
			retried: BOOLEAN
		do
			if retried then
				Result := True
			else
				create argument.make_from_string_general ("argument")
				argument.append_code (0)
				create arguments.make (1)
				arguments.extend (argument)
				create command.make ("git", arguments)
			end
		rescue
			retried := True
			retry
		end

	nul_directory_rejected: BOOLEAN
			-- Does configuration reject NUL in a working directory?
		local
			command: OS_COMMAND
			directory_name: STRING_32
			retried: BOOLEAN
		do
			if retried then
				Result := True
			else
				create command.make ("git", <<"--version">>)
				create directory_name.make_from_string_general ("directory")
				directory_name.append_code (0)
				command.set_working_directory (directory_name)
			end
		rescue
			retried := True
			retry
		end

	nul_shell_command_rejected: BOOLEAN
			-- Does shell-command creation reject NUL in command text?
		local
			command: OS_COMMAND
			command_text: STRING_32
			retried: BOOLEAN
		do
			if retried then
				Result := True
			else
				create command_text.make_from_string_general ("echo")
				command_text.append_code (0)
				create command.make_shell (command_text)
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
			check
				attached test_root as root
			then
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

	assert_readable_strings_equal (a_tag: STRING_8; a_expected, a_actual: READABLE_STRING_8)
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
