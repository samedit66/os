note

	description:
	"[
        Internal owner of a native process handle, its pipe workers, captured
        output, failures, and lifecycle state. The executable path and complete
        environment are resolved by `OS_COMMAND` before entry to the native
        layer, so Unix and Windows launch the same configured snapshot.
    ]"
	author: "samedit66 <samedit66@yandex.ru>"
	library: "os"
	warning: "Internal implementation class; client code should use `OS_COMMAND`."

class OS_PROCESS

create {OS_COMMAND}

	make,
	make_unresolved

feature {NONE} -- Initialization

	make (a_executable: READABLE_STRING_GENERAL; a_arguments: ITERABLE [READABLE_STRING_GENERAL]; a_stdout: detachable PROCEDURE [READABLE_STRING_8]; a_stderr: detachable PROCEDURE [READABLE_STRING_8]; a_working_directory: detachable READABLE_STRING_GENERAL; a_input: READABLE_STRING_8; a_environment: ITERABLE [READABLE_STRING_GENERAL]; a_stdin_mode, a_stdout_mode, a_stderr_mode, a_timeout_milliseconds: INTEGER; a_allow_terminal_stdin: BOOLEAN)
			-- Launch the native process and its Eiffel pipe workers with `a_environment`.
			-- Environment entries are encoded as UTF-8 on Unix. On Windows the
			-- native bridge converts them to a sorted UTF-16 environment block.
		require
			valid_stdin_mode: a_stdin_mode = stdin_pipe_mode or else a_stdin_mode = stdin_inherit_mode
			valid_stdout_mode: a_stdout_mode >= output_capture_mode and then a_stdout_mode <= output_discard_mode
			valid_stderr_mode: a_stderr_mode >= output_capture_mode and then a_stderr_mode <= stderr_merge_mode
			valid_timeout: a_timeout_milliseconds >= 0
		do
			initialize_state
			stdout_was_captured := a_stdout_mode = output_capture_mode
			stderr_was_captured := a_stderr_mode = output_capture_mode
			stderr_was_merged := a_stderr_mode = stderr_merge_mode
			stdin_was_piped := a_stdin_mode = stdin_pipe_mode
			timeout_milliseconds := a_timeout_milliseconds
			launch_process (a_executable, a_arguments, a_stdout, a_stderr, a_working_directory, a_input, a_environment, a_stdin_mode, a_stdout_mode, a_stderr_mode, a_allow_terminal_stdin)
		ensure
			launch_failure_is_terminal: not was_launched implies is_finished
		end

	make_unresolved (a_executable: READABLE_STRING_GENERAL; a_stdout_was_captured, a_stderr_was_captured, a_stderr_was_merged: BOOLEAN)
			-- Publish a launch failure because `a_executable` could not be resolved.
			-- This preserves the same terminal result on Unix and Windows without
			-- allowing either platform to fall back to the parent process PATH.
		local
			failure: OS_PROCESS_FAILURE
		do
			initialize_state
			stdout_was_captured := a_stdout_was_captured
			stderr_was_captured := a_stderr_was_captured
			stderr_was_merged := a_stderr_was_merged
			create failure.make (new_launch_kind, "launch", "Cannot resolve executable through command environment")
			record_failure (failure)
			process_exited := True
			complete
		ensure
			not_launched: not was_launched
			finished: is_finished
		end

	initialize_state
			-- Establish empty lifecycle and result storage before launch.
		do
			create lifecycle_mutex.make
			create wait_mutex.make
			create state_mutex.make
			create failure_storage.make (4)
			create stdout_snapshot.make_empty
			create stderr_snapshot.make_empty
			create supervisor.make (agent supervise)
		end

	launch_process (a_executable: READABLE_STRING_GENERAL; a_arguments: ITERABLE [READABLE_STRING_GENERAL]; a_stdout: detachable PROCEDURE [READABLE_STRING_8]; a_stderr: detachable PROCEDURE [READABLE_STRING_8]; a_working_directory: detachable READABLE_STRING_GENERAL; a_input: READABLE_STRING_8; a_environment: ITERABLE [READABLE_STRING_GENERAL]; a_stdin_mode, a_stdout_mode, a_stderr_mode: INTEGER; a_allow_terminal_stdin: BOOLEAN)
			-- Launch after all recovery state has been initialized.
		local
			executable_c: C_STRING
			argument_strings: ARRAYED_LIST [C_STRING]
			environment_strings: ARRAYED_LIST [C_STRING]
			argument_vector: MANAGED_POINTER
			environment_vector: MANAGED_POINTER
			error_area: MANAGED_POINTER
			working_directory_c: detachable C_STRING
			out_reader: OS_PROCESS_PIPE_READER
			err_reader: OS_PROCESS_PIPE_READER
			in_writer: OS_PROCESS_PIPE_WRITER
			working_directory_pointer: POINTER
			offset: INTEGER
			launch_error: INTEGER
			terminal_stdin_flag: INTEGER
		do
			create executable_c.make (utf_8 (a_executable))
			create argument_strings.make (8)
			argument_strings.extend (executable_c)
			across
				a_arguments
			as
				argument
			loop
				argument_strings.extend (create {C_STRING}.make (utf_8 (argument)))
			end
			create argument_vector.make ((argument_strings.count + 1) * {PLATFORM}.pointer_bytes)
			across
				argument_strings
			as
				argument
			loop
				argument_vector.put_pointer (argument.item, offset)
				offset := offset + {PLATFORM}.pointer_bytes
			end
			argument_vector.put_pointer (default_pointer, offset)
			create environment_strings.make (40)
			across
				a_environment
			as
				entry
			loop
				environment_strings.extend (create {C_STRING}.make (utf_8 (entry)))
			end
			create environment_vector.make ((environment_strings.count + 1) * {PLATFORM}.pointer_bytes)
			offset := 0
			across
				environment_strings
			as
				entry
			loop
				environment_vector.put_pointer (entry.item, offset)
				offset := offset + {PLATFORM}.pointer_bytes
			end
			environment_vector.put_pointer (default_pointer, offset)
			if attached a_working_directory as directory then
				create working_directory_c.make (utf_8 (directory))
				working_directory_pointer := working_directory_c.item
			end
			create error_area.make ({PLATFORM}.integer_32_bytes)
			if a_allow_terminal_stdin then
				terminal_stdin_flag := 1
			end
			native_handle := c_start (executable_c.item, argument_vector.item, environment_vector.item, working_directory_pointer, a_stdin_mode, a_stdout_mode, a_stderr_mode, terminal_stdin_flag, error_area.item)
			if native_handle = default_pointer then
				launch_error := error_area.read_integer_32 (0)
				record_native_failure (new_launch_kind, "launch", "Cannot start process", launch_error)
				process_exited := True
				complete
			else
				was_launched := True
				if stdout_was_captured then
					create out_reader.make (native_handle, True, a_stdout)
					stdout_reader := out_reader
					out_reader.launch
					if out_reader.is_last_launch_successful then
						stdout_reader_launched := True
					else
						record_worker_initialization_failure ("initialize stdout worker")
					end
				end
				if stderr_was_captured and then not has_worker_initialization_failure then
					create err_reader.make (native_handle, False, a_stderr)
					stderr_reader := err_reader
					err_reader.launch
					if err_reader.is_last_launch_successful then
						stderr_reader_launched := True
					else
						record_worker_initialization_failure ("initialize stderr worker")
					end
				end
				if stdin_was_piped and then not has_worker_initialization_failure then
					create in_writer.make (native_handle, a_input)
					stdin_writer := in_writer
					in_writer.launch
					if in_writer.is_last_launch_successful then
						stdin_writer_launched := True
					else
						record_worker_initialization_failure ("initialize stdin worker")
					end
				end
				if has_worker_initialization_failure then
					rollback_initialization
				else
					supervisor.launch
					if supervisor.is_last_launch_successful then
						supervisor_launched := True
					else
						record_worker_initialization_failure ("initialize process supervisor")
						rollback_initialization
					end
				end
			end
		rescue
			if was_launched and then not is_finished then
				rollback_initialization
			end
		end

feature {OS_COMMAND} -- Access

	execution_result: OS_PROCESS_EXECUTION_RESULT
			-- Completed execution result.
		require
			finished: is_finished
		local
			snapshot: detachable OS_PROCESS_EXECUTION_RESULT
		do
			state_mutex.lock
			snapshot := process_execution_result
			state_mutex.unlock
			check
				attached snapshot as completed_result
			then
				Result := completed_result
			end
		end

	failures: READABLE_INDEXABLE [OS_PROCESS_FAILURE]
			-- Failures recorded so far in deterministic order.
		do
			Result := failure_snapshot
		end

feature {OS_COMMAND} -- Status report

	is_finished: BOOLEAN
			-- Is the terminal execution result available?
		do
			state_mutex.lock
			Result := finished
			state_mutex.unlock
		end

	has_failures: BOOLEAN
			-- Have any process-library failures been recorded?
		local
			snapshot: READABLE_INDEXABLE [OS_PROCESS_FAILURE]
		do
			snapshot := failures
			Result := snapshot.lower <= snapshot.upper
		end

feature {OS_COMMAND} -- Basic operations

	wait
			-- Synchronize with autonomous supervision and result publication.
		local
			mutex_locked: BOOLEAN
		do
			wait_mutex.lock
			mutex_locked := True
			if supervisor_launched then
				supervisor.join
			end
			wait_mutex.unlock
			mutex_locked := False
		ensure
			finished: is_finished
		rescue
			if mutex_locked then
				wait_mutex.unlock
			end
		end

	terminate
			-- Force termination of the managed process tree.
		local
			status: INTEGER
			mutex_locked: BOOLEAN
		do
			lifecycle_mutex.lock
			mutex_locked := True
			if not is_finished and then native_handle /= default_pointer and then not was_timed_out then
				status := c_terminate (native_handle)
				if status /= 0 then
					record_native_failure (new_termination_kind, "terminate", "Cannot terminate process", status)
				else
					was_terminated_by_client := True
				end
			end
			lifecycle_mutex.unlock
			mutex_locked := False
		rescue
			if mutex_locked then
				lifecycle_mutex.unlock
			end
		end

feature {NONE} -- Completion

	supervise
			-- Own native waiting, worker completion, cleanup, and result publication.
			-- Callback workers are joined here. Client callbacks supplied to
			-- `start_streaming` must therefore return for completion to progress.
		do
			wait_for_process
			if timeout_milliseconds > 0 and then not has_termination_reason then
				wait_for_io_until_deadline
			end
			if has_termination_reason then
				drain_io_after_termination
			elseif timeout_milliseconds = 0 then
				wait_for_io
				if has_termination_reason then
					drain_io_after_termination
				end
			end
			join_workers
			complete
		end

	rollback_initialization
			-- Restore safe ownership after an I/O worker failed to start.
		local
			exit_area: MANAGED_POINTER
			status: INTEGER
		do
			if was_launched and then native_handle /= default_pointer then
				if stdin_was_piped and then not stdin_writer_launched then
					status := c_close_stdin (native_handle)
					if status /= 0 then
						record_native_failure (new_stdin_close_kind, "close stdin during initialization rollback", "Cannot close standard input during initialization rollback", status)
					end
				end
				status := c_force_terminate (native_handle)
				if status /= 0 then
					record_native_failure (new_termination_kind, "force terminate during initialization rollback", "Cannot force process termination during initialization rollback", status)
				end
				create exit_area.make ({PLATFORM}.integer_32_bytes)
				status := c_wait (native_handle, exit_area.item)
				if status = 0 then
					exit_status := exit_area.read_integer_32 (0)
					process_exited := True
					join_workers
					complete
				else
					record_native_failure (new_wait_kind, "wait during initialization rollback", "Cannot wait for process during initialization rollback", status)
					raise_unsafe_lifecycle_failure ("Cannot restore process ownership after worker initialization failure", status)
				end
			end
		end

	wait_for_process
			-- Wait for the child, recovering ownership after a native wait failure.
		local
			exit_area: MANAGED_POINTER
			timed_out_area: MANAGED_POINTER
			status: INTEGER
		do
			if not process_exited then
				create exit_area.make ({PLATFORM}.integer_32_bytes)
				if timeout_milliseconds > 0 then
					create timed_out_area.make ({PLATFORM}.integer_32_bytes)
					status := c_wait_for (native_handle, timeout_milliseconds, timed_out_area.item, exit_area.item)
					if status = 0 and then timed_out_area.read_integer_32 (0) /= 0 then
						terminate_after_timeout
						status := c_wait (native_handle, exit_area.item)
					end
				else
					status := c_wait (native_handle, exit_area.item)
				end
				if status /= 0 then
					record_native_failure (new_wait_kind, "wait", "Cannot wait for process", status)
					recover_after_wait_failure (exit_area)
				else
					exit_status := exit_area.read_integer_32 (0)
					process_exited := True
				end
			end
		ensure
			process_exited: process_exited
		end

	wait_for_io_until_deadline
			-- Allow pipe workers to finish only within the overall execution deadline.
		local
			environment: EXECUTION_ENVIRONMENT
			remaining: INTEGER
		do
			create environment
			from
				remaining := c_timeout_remaining (native_handle, timeout_milliseconds)
			until
				io_finished or else remaining = 0 or else has_termination_reason
			loop
				environment.sleep (io_check_interval_nanoseconds)
				remaining := c_timeout_remaining (native_handle, timeout_milliseconds)
			end
			if not io_finished and then not has_termination_reason then
				terminate_after_timeout
			end
		end

	wait_for_io
			-- Wait for natural EOF before joining workers from the supervisor thread.
		local
			environment: EXECUTION_ENVIRONMENT
		do
			create environment
			from
			until
				io_finished or else has_termination_reason
			loop
				environment.sleep (io_check_interval_nanoseconds)
			end
		end

	terminate_after_timeout
			-- Record the expired deadline and force the managed process tree down.
		local
			status: INTEGER
		do
			lifecycle_mutex.lock
			if not was_terminated_by_client and then not was_timed_out then
				was_timed_out := True
				if native_handle /= default_pointer then
					status := c_terminate (native_handle)
					if status /= 0 then
						record_native_failure (new_termination_kind, "terminate after timeout", "Cannot terminate timed-out process tree", status)
					end
				end
			end
			lifecycle_mutex.unlock
		end

	has_termination_reason: BOOLEAN
			-- Has client termination or the deadline initiated shutdown?
		do
			lifecycle_mutex.lock
			Result := was_terminated_by_client or else was_timed_out
			lifecycle_mutex.unlock
		end

	drain_io_after_termination
			-- Give killed descendants a bounded interval to close inherited pipes.
		local
			environment: EXECUTION_ENVIRONMENT
			attempts: INTEGER
		do
			create environment
			from
			until
				io_finished or else attempts = post_termination_drain_attempts
			loop
				environment.sleep (io_check_interval_nanoseconds)
				attempts := attempts + 1
			end
			if not io_finished then
				output_was_cut_off := (stdout_reader_launched and then attached stdout_reader as out_reader and then not out_reader.is_finished) or else (stderr_reader_launched and then attached stderr_reader as err_reader and then not err_reader.is_finished)
				lifecycle_mutex.lock
				if native_handle /= default_pointer then
					c_cancel_io (native_handle)
				end
				lifecycle_mutex.unlock
			end
		end

	recover_after_wait_failure (a_exit_area: MANAGED_POINTER)
			-- Force cleanup and recover a known reaped state after wait failure.
		local
			status: INTEGER
		do
			status := c_force_terminate (native_handle)
			if status /= 0 then
				record_native_failure (new_termination_kind, "force terminate after wait failure", "Cannot force process termination after wait failure", status)
			end
			status := c_wait (native_handle, a_exit_area.item)
			if status = 0 then
				exit_status := a_exit_area.read_integer_32 (0)
				process_exited := True
			else
				record_native_failure (new_wait_kind, "recovery wait", "Cannot recover process ownership after wait failure", status)
				raise_unsafe_lifecycle_failure ("Cannot restore process ownership after wait failure", status)
			end
		end

	io_finished: BOOLEAN
			-- Have all launched standard-I/O workers terminated?
		do
			Result := (not stdout_reader_launched or else (attached stdout_reader as out_reader and then out_reader.is_finished)) and then (not stderr_reader_launched or else (attached stderr_reader as err_reader and then err_reader.is_finished)) and then (not stdin_writer_launched or else (attached stdin_writer as in_writer and then in_writer.is_finished))
		end

	join_workers
			-- Join every successfully launched I/O worker.
		do
			if stdout_reader_launched and then attached stdout_reader as out_reader then
				out_reader.join
				stdout_reader_joined := True
			end
			if stderr_reader_launched and then attached stderr_reader as err_reader then
				err_reader.join
				stderr_reader_joined := True
			end
			if stdin_writer_launched and then attached stdin_writer as in_writer then
				in_writer.join
				stdin_writer_joined := True
			end
		ensure
			joined: io_workers_joined
		end

	io_workers_joined: BOOLEAN
			-- Have all launched standard-I/O workers been joined?
		do
			Result := (not stdout_reader_launched or else stdout_reader_joined) and then (not stderr_reader_launched or else stderr_reader_joined) and then (not stdin_writer_launched or else stdin_writer_joined)
		end

	complete
			-- Publish the sole terminal result and release the native handle.
		require
			process_exited: process_exited
			io_workers_joined: io_workers_joined
		local
			result_failures: READABLE_INDEXABLE [OS_PROCESS_FAILURE]
			completed_result: OS_PROCESS_EXECUTION_RESULT
			status: INTEGER
		do
			if not is_finished then
				if attached stdout_reader as out_reader then
					stdout_snapshot := out_reader.output.to_string_8
				end
				if attached stderr_reader as err_reader then
					stderr_snapshot := err_reader.output.to_string_8
				end
				lifecycle_mutex.lock
				if native_handle /= default_pointer then
					status := c_restore_terminal (native_handle)
					if status /= 0 then
						record_native_failure (new_wait_kind, "restore terminal", "Cannot restore the parent terminal foreground process group", status)
					end
					c_free (native_handle)
					native_handle := default_pointer
				end
				lifecycle_mutex.unlock
				result_failures := failure_snapshot
				create completed_result.make (was_launched, was_launched and process_exited, exit_status, stdout_was_captured, stderr_was_captured, stderr_was_merged, was_terminated_by_client, was_timed_out, output_was_cut_off, stdout_snapshot, stderr_snapshot, result_failures)
				state_mutex.lock
				process_execution_result := completed_result
				finished := True
				state_mutex.unlock
			end
		ensure
			finished: is_finished
			result_attached: attached process_execution_result
			handle_released: native_handle = default_pointer
		end

feature {NONE} -- Failures

	record_failure (a_failure: OS_PROCESS_FAILURE)
			-- Record `a_failure` once per category and operation.
		local
			already_recorded: BOOLEAN
		do
			state_mutex.lock
			across
				failure_storage
			as
				failure
			until
				already_recorded
			loop
				already_recorded := failure.kind.same_category (a_failure.kind) and then failure.operation.same_string (a_failure.operation)
			end
			if not already_recorded then
				failure_storage.extend (a_failure)
			end
			state_mutex.unlock
		end

	record_native_failure (a_kind: OS_PROCESS_FAILURE_KIND; a_operation: READABLE_STRING_8; a_description: READABLE_STRING_8; a_native_code: INTEGER)
			-- Record a native failure.
		require
			positive_native_code: a_native_code > 0
		local
			failure: OS_PROCESS_FAILURE
		do
			create failure.make_with_native_code (a_kind, a_operation, a_description, a_native_code)
			record_failure (failure)
		end

	record_worker_initialization_failure (a_operation: READABLE_STRING_8)
			-- Record failure to start one Eiffel I/O worker.
		local
			failure: OS_PROCESS_FAILURE
		do
			create failure.make (new_worker_initialization_kind, a_operation, "Cannot initialize process I/O worker")
			record_failure (failure)
		end

	has_worker_initialization_failure: BOOLEAN
			-- Has any I/O worker failed to start?
		local
			snapshot: ARRAYED_LIST [OS_PROCESS_FAILURE]
		do
			state_mutex.lock
			snapshot := failure_storage.twin
			state_mutex.unlock
			across
				snapshot
			as
				failure
			until
				Result
			loop
				Result := failure.kind.is_worker_initialization
			end
		end

	failure_snapshot: READABLE_INDEXABLE [OS_PROCESS_FAILURE]
			-- All current failures in canonical deterministic order.
		local
			raw_failures: ARRAYED_LIST [OS_PROCESS_FAILURE]
			ordered_failures: ARRAYED_LIST [OS_PROCESS_FAILURE]
			rank: INTEGER
		do
			state_mutex.lock
			raw_failures := failure_storage.twin
			state_mutex.unlock
			if attached stdin_writer as in_writer then
				append_failures (raw_failures, in_writer.failures)
			end
			if attached stdout_reader as out_reader then
				append_failures (raw_failures, out_reader.failures)
			end
			if attached stderr_reader as err_reader then
				append_failures (raw_failures, err_reader.failures)
			end
			create ordered_failures.make (raw_failures.count)
			from
				rank := 1
			until
				rank > failure_category_count
			loop
				across
					raw_failures
				as
					failure
				loop
					if failure_rank (failure.kind) = rank then
						ordered_failures.extend (failure)
					end
				end
				rank := rank + 1
			end
			Result := ordered_failures
		end

	append_failures (a_target: ARRAYED_LIST [OS_PROCESS_FAILURE]; a_source: READABLE_INDEXABLE [OS_PROCESS_FAILURE])
			-- Append `a_source` to `a_target`.
		do
			across
				a_source
			as
				failure
			loop
				a_target.extend (failure)
			end
		end

	failure_rank (a_kind: OS_PROCESS_FAILURE_KIND): INTEGER
			-- Canonical ordering rank of `a_kind`.
		do
			if a_kind.is_launch then
				Result := 1
			elseif a_kind.is_worker_initialization then
				Result := 2
			elseif a_kind.is_termination then
				Result := 3
			elseif a_kind.is_wait then
				Result := 4
			elseif a_kind.is_stdin_write then
				Result := 5
			elseif a_kind.is_stdin_close then
				Result := 6
			elseif a_kind.is_stdout_read then
				Result := 7
			elseif a_kind.is_stdout_handler then
				Result := 8
			elseif a_kind.is_stderr_read then
				Result := 9
			else
				Result := 10
			end
		ensure
			valid_rank: Result >= 1 and Result <= failure_category_count
		end

feature {NONE} -- Failure-kind factories

	new_launch_kind: OS_PROCESS_FAILURE_KIND
		do
			create Result.make_launch
		end

	new_stdin_close_kind: OS_PROCESS_FAILURE_KIND
		do
			create Result.make_stdin_close
		end

	new_wait_kind: OS_PROCESS_FAILURE_KIND
		do
			create Result.make_wait
		end

	new_termination_kind: OS_PROCESS_FAILURE_KIND
		do
			create Result.make_termination
		end

	new_worker_initialization_kind: OS_PROCESS_FAILURE_KIND
		do
			create Result.make_worker_initialization
		end

feature {NONE} -- Conversion

	utf_8 (a_text: READABLE_STRING_GENERAL): STRING_8
			-- UTF-8 representation of `a_text`.
		do
			Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text)
		end

feature {NONE} -- Exceptional invariant recovery

	raise_unsafe_lifecycle_failure (a_operation: READABLE_STRING_8; a_code: INTEGER)
			-- Raise because safe native child ownership could not be restored.
		local
			message: STRING_8
		do
			create message.make_from_string (a_operation)
			message.append (" (native error ")
			message.append_integer (a_code)
			message.append_character (')')
			(create {EXCEPTIONS}).raise (message)
		end

feature {NONE} -- Native bridge

	c_start (a_executable, a_arguments, a_environment, a_working_directory: POINTER; a_stdin_mode, a_stdout_mode, a_stderr_mode, a_allow_terminal_stdin: INTEGER; a_error: POINTER): POINTER
		external
			"C use <subprocess.h>"
		alias
			"os_process_start"
		end

	c_wait (a_process, a_exit_code: POINTER): INTEGER
		external
			"C blocking use <subprocess.h>"
		alias
			"os_process_wait"
		end

	c_wait_for (a_process: POINTER; a_timeout_milliseconds: INTEGER; a_timed_out, a_exit_code: POINTER): INTEGER
		external
			"C blocking use <subprocess.h>"
		alias
			"os_process_wait_for"
		end

	c_timeout_remaining (a_process: POINTER; a_timeout_milliseconds: INTEGER): INTEGER
		external
			"C use <subprocess.h>"
		alias
			"os_process_timeout_remaining"
		end

	c_restore_terminal (a_process: POINTER): INTEGER
		external
			"C use <subprocess.h>"
		alias
			"os_process_restore_terminal"
		end

	c_terminate (a_process: POINTER): INTEGER
		external
			"C use <subprocess.h>"
		alias
			"os_process_terminate"
		end

	c_force_terminate (a_process: POINTER): INTEGER
		external
			"C use <subprocess.h>"
		alias
			"os_process_force_terminate"
		end

	c_close_stdin (a_process: POINTER): INTEGER
		external
			"C use <subprocess.h>"
		alias
			"os_process_close_stdin"
		end

	c_cancel_io (a_process: POINTER)
		external
			"C use <subprocess.h>"
		alias
			"os_process_cancel_io"
		end

	c_free (a_process: POINTER)
		external
			"C use <subprocess.h>"
		alias
			"os_process_free"
		end

feature {NONE} -- Implementation

	native_handle: POINTER

	stdout_reader: detachable OS_PROCESS_PIPE_READER

	stderr_reader: detachable OS_PROCESS_PIPE_READER

	stdin_writer: detachable OS_PROCESS_PIPE_WRITER

	stdout_reader_launched: BOOLEAN

	stderr_reader_launched: BOOLEAN

	stdin_writer_launched: BOOLEAN

	stdout_reader_joined: BOOLEAN

	stderr_reader_joined: BOOLEAN

	stdin_writer_joined: BOOLEAN

	stdout_snapshot: STRING_8

	stderr_snapshot: STRING_8

	stdin_was_piped: BOOLEAN

	stdout_was_captured: BOOLEAN

	stderr_was_captured: BOOLEAN

	stderr_was_merged: BOOLEAN

	was_terminated_by_client: BOOLEAN

	was_timed_out: BOOLEAN

	output_was_cut_off: BOOLEAN

	timeout_milliseconds: INTEGER

	stdin_pipe_mode: INTEGER = 0
	stdin_inherit_mode: INTEGER = 1
	output_capture_mode: INTEGER = 0
	output_inherit_mode: INTEGER = 1
	output_discard_mode: INTEGER = 2
	stderr_merge_mode: INTEGER = 3
			-- Values shared with the constants in `subprocess.h`.

	process_execution_result: detachable OS_PROCESS_EXECUTION_RESULT

	failure_storage: ARRAYED_LIST [OS_PROCESS_FAILURE]

	lifecycle_mutex: MUTEX

	wait_mutex: MUTEX
			-- Serialize clients joining the sole supervisor thread.

	state_mutex: MUTEX

	supervisor: WORKER_THREAD

	supervisor_launched: BOOLEAN

	was_launched: BOOLEAN

	exit_status: INTEGER

	process_exited: BOOLEAN

	finished: BOOLEAN

	failure_category_count: INTEGER = 10

	io_check_interval_nanoseconds: INTEGER_64 = 10_000_000

	post_termination_drain_attempts: INTEGER = 100
			-- Ten-millisecond checks give terminated pipes one second to reach EOF.

invariant

	finished_process_exited: finished implies process_exited
	finished_handle_released: finished implies native_handle = default_pointer
	finished_has_result: finished implies attached process_execution_result
	result_is_terminal: attached process_execution_result implies finished
	handle_belongs_to_launched_process: native_handle /= default_pointer implies was_launched

end
