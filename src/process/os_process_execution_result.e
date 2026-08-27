class
    OS_PROCESS_EXECUTION_RESULT

create {OS_PROCESS}
    make

feature {NONE} -- Initialization

    make (
        a_was_launched: BOOLEAN;
        a_has_exit_code: BOOLEAN;
        a_exit_code: INTEGER;
        a_stdout: READABLE_STRING_8;
        a_stderr: READABLE_STRING_8;
        a_failures: ITERABLE [OS_PROCESS_FAILURE]
    )
            -- Create an immutable execution snapshot.
        require
            exit_code_requires_launch: a_has_exit_code implies a_was_launched
        do
            was_launched := a_was_launched
            has_exit_code := a_has_exit_code
            exit_code_storage := a_exit_code
            create stdout_storage.make_from_string (a_stdout)
            create stderr_storage.make_from_string (a_stderr)
            create failure_storage.make (4)
            across a_failures as failure loop
                failure_storage.extend (failure)
            end
        ensure
            launch_set: was_launched = a_was_launched
            exit_code_presence_set: has_exit_code = a_has_exit_code
            exit_code_set: a_has_exit_code implies exit_code = a_exit_code
            stdout_copied: stdout.same_string (a_stdout)
            stderr_copied: stderr.same_string (a_stderr)
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
        do
            Result := stdout_storage
        end

    stderr: READABLE_STRING_8
            -- Captured standard-error bytes.
        do
            Result := stderr_storage
        end

    failures: READABLE_INDEXABLE [OS_PROCESS_FAILURE]
            -- Defensive snapshot of library failures.
        local
            snapshot: ARRAYED_LIST [OS_PROCESS_FAILURE]
        do
            create snapshot.make (failure_storage.count)
            across failure_storage as failure loop
                snapshot.extend (failure)
            end
            Result := snapshot
        ensure
            count_preserved:
                Result.upper - Result.lower + 1 = failure_storage.count
        end

feature -- Status report

    was_launched: BOOLEAN
            -- Was a child process successfully launched?

    has_exit_code: BOOLEAN
            -- Is a child completion code available?

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
            Result := was_launched and then has_exit_code and then
                exit_code_storage = 0 and then not has_failures
        ensure
            definition: Result =
                (was_launched and then has_exit_code and then
                 exit_code = 0 and then not has_failures)
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
    failed_iff_failures_present: has_failures = not failure_storage.is_empty

end
