note

	description:
	"[
        Immutable snapshot of a completed process execution, including launch
        status, optional exit code, captured output, and structured failures.
    ]"
	author: "samedit66 <samedit66@yandex.ru>"
	library: "os"

class OS_PROCESS_EXECUTION_RESULT

create {OS_PROCESS}

	make

feature {NONE} -- Initialization

	make (a_was_launched: BOOLEAN; a_has_exit_code: BOOLEAN; a_exit_code: INTEGER; a_stdout_was_captured, a_stderr_was_captured, a_stderr_was_merged, a_was_terminated_by_client, a_was_timed_out, a_output_was_cut_off: BOOLEAN; a_stdout: READABLE_STRING_8; a_stderr: READABLE_STRING_8; a_failures: ITERABLE [OS_PROCESS_FAILURE])
			-- Create an immutable execution snapshot.
		require
			exit_code_requires_launch: a_has_exit_code implies a_was_launched
			merged_stderr_not_separately_captured: a_stderr_was_merged implies not a_stderr_was_captured
			termination_reasons_exclusive: not (a_was_terminated_by_client and a_was_timed_out)
		do
			was_launched := a_was_launched
			has_exit_code := a_has_exit_code
			exit_code_storage := a_exit_code
			stdout_was_captured := a_stdout_was_captured
			stderr_was_captured := a_stderr_was_captured
			stderr_was_merged := a_stderr_was_merged
			was_terminated_by_client := a_was_terminated_by_client
			was_timed_out := a_was_timed_out
			output_was_cut_off := a_output_was_cut_off
			create stdout_storage.make_from_string (a_stdout)
			create stderr_storage.make_from_string (a_stderr)
			create failure_storage.make (4)
			across
				a_failures
			as
				failure
			loop
				failure_storage.extend (failure)
			end
		ensure
			launch_set: was_launched = a_was_launched
			exit_code_presence_set: has_exit_code = a_has_exit_code
			exit_code_set: a_has_exit_code implies exit_code = a_exit_code
			stdout_copied: a_stdout_was_captured implies stdout.same_string (a_stdout)
			stderr_copied: a_stderr_was_captured implies stderr.same_string (a_stderr)
		end

feature -- Access

	exit_code: INTEGER
			-- Child exit code.
		require
			has_exit_code: has_exit_code
		do
			Result := exit_code_storage
		end

	stdout: READABLE_STRING_8
			-- Captured standard-output bytes.
		require
			was_captured: stdout_was_captured
		do
			Result := stdout_storage
		end

	stderr: READABLE_STRING_8
			-- Captured standard-error bytes.
		require
			was_captured: stderr_was_captured
		do
			Result := stderr_storage
		end

	failures: READABLE_INDEXABLE [OS_PROCESS_FAILURE]
			-- Defensive snapshot of library failures.
		local
			snapshot: ARRAYED_LIST [OS_PROCESS_FAILURE]
		do
			create snapshot.make (failure_storage.count)
			across
				failure_storage
			as
				failure
			loop
				snapshot.extend (failure)
			end
			Result := snapshot
		ensure
			count_preserved: Result.upper - Result.lower + 1 = failure_storage.count
		end

feature -- Status report

	was_launched: BOOLEAN
			-- Was a child process successfully launched?

	has_exit_code: BOOLEAN
			-- Is a child completion code available?

	stdout_was_captured: BOOLEAN
			-- Was standard output captured and retained in `stdout`?

	stderr_was_captured: BOOLEAN
			-- Was standard error captured separately and retained in `stderr`?

	stderr_was_merged: BOOLEAN
			-- Was standard error redirected to the standard-output destination?

	was_terminated_by_client: BOOLEAN
			-- Did a client termination request end the managed execution?

	was_timed_out: BOOLEAN
			-- Did the configured overall execution deadline expire?

	output_was_cut_off: BOOLEAN
			-- Was captured output forcibly stopped before all pipe endpoints reached EOF?

	has_failures: BOOLEAN
			-- Did the process library record any failures?
		do
			Result := not failure_storage.is_empty
		ensure
			definition: Result = (failures.lower <= failures.upper)
		end

	successful: BOOLEAN
			-- Was the child launched, exited with zero, and free of library failures?
		do
			Result := was_launched and then has_exit_code and then exit_code_storage = 0 and then not has_failures and then not was_terminated_by_client and then not was_timed_out
		ensure
			definition: Result = (was_launched and then has_exit_code and then exit_code = 0 and then not has_failures and then not was_terminated_by_client and then not was_timed_out)
		end

feature {NONE} -- Implementation

	exit_code_storage: INTEGER
			-- Stored child completion code, when available.

	stdout_storage: IMMUTABLE_STRING_8
			-- Immutable standard-output snapshot.

	stderr_storage: IMMUTABLE_STRING_8
			-- Immutable standard-error snapshot.

	failure_storage: ARRAYED_LIST [OS_PROCESS_FAILURE]
			-- Private ordered failure snapshot.

invariant

	exit_code_requires_launch: has_exit_code implies was_launched
	merged_stderr_not_separately_captured: stderr_was_merged implies not stderr_was_captured
	termination_reasons_exclusive: not (was_terminated_by_client and was_timed_out)
	failed_iff_failures_present: has_failures = not failure_storage.is_empty

end
