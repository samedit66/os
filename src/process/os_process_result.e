class
    OS_PROCESS_RESULT

create
    make

feature {NONE} -- Initialization

    make (
        a_exit_code: INTEGER;
        a_stdout: READABLE_STRING_8;
        a_stderr: READABLE_STRING_8
    )
            -- Create a result with copied output snapshots.
        do
            exit_code := a_exit_code
            stdout := a_stdout.to_string_8
            stderr := a_stderr.to_string_8
        ensure
            exit_code_set: exit_code = a_exit_code
            stdout_copied: stdout.same_string (a_stdout)
            stderr_copied: stderr.same_string (a_stderr)
        end

feature -- Access

    exit_code: INTEGER
            -- Child exit code; termination reporting follows the selected backend.

    stdout: STRING_8
            -- Captured standard-output bytes.

    stderr: STRING_8
            -- Captured standard-error bytes.

feature -- Status report

    successful: BOOLEAN
            -- Did the child exit normally with code zero?
        do
            Result := exit_code = 0
        ensure
            definition: Result = (exit_code = 0)
        end

end
