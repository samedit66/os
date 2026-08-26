class
    OS_PROCESS_RESULT

create {OS_PROCESS}
    make_launched,
    make_launch_failure

feature {NONE} -- Initialization

    make_launched (
        a_exit_code: INTEGER;
        a_stdout: READABLE_STRING_8;
        a_stderr: READABLE_STRING_8
    )
            -- Create a result for a launched child with copied output snapshots.
        do
            was_launched := True
            exit_code := a_exit_code
            create stdout_storage.make_from_string (a_stdout)
            create stderr_storage.make_from_string (a_stderr)
        ensure
            launched: was_launched
            exit_code_set: exit_code = a_exit_code
            stdout_copied: stdout.same_string (a_stdout)
            stderr_copied: stderr.same_string (a_stderr)
        end

    make_launch_failure
            -- Create a result for a child that could not be launched.
        do
            exit_code := command_launch_failure
            create stdout_storage.make_empty
            create stderr_storage.make_empty
        ensure
            not_launched: not was_launched
            conventional_exit_code: exit_code = command_launch_failure
            stdout_empty: stdout.is_empty
            stderr_empty: stderr.is_empty
        end

feature -- Access

    exit_code: INTEGER
            -- Child exit code, or 127 if the child was not launched.
            -- Termination reporting follows the selected backend.

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

feature -- Status report

    was_launched: BOOLEAN
            -- Was a child process successfully launched?

    successful: BOOLEAN
            -- Was the child launched and reported exit code zero?
        do
            Result := was_launched and exit_code = 0
        ensure
            definition: Result = (was_launched and exit_code = 0)
        end

feature {NONE} -- Implementation

    stdout_storage: IMMUTABLE_STRING_8
            -- Immutable standard-output snapshot.

    stderr_storage: IMMUTABLE_STRING_8
            -- Immutable standard-error snapshot.

    command_launch_failure: INTEGER = 127

invariant
    launch_failure_exit_code: not was_launched implies exit_code = command_launch_failure
    launch_failure_stdout_empty: not was_launched implies stdout.is_empty
    launch_failure_stderr_empty: not was_launched implies stderr.is_empty

end
