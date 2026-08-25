class
    APPLICATION

create
    make

feature {NONE} -- Initialization

    make
            -- Run a small streaming example.
        local
            runner: OS_PROCESS_RUNNER
            process: OS_PROCESS_HANDLE
        do
            create runner
            process := runner.start (
                "git",
                << "--version" >>,
                agent on_stdout,
                agent on_stderr
            )
            process.wait

            io.put_string ("Exit code: ")
            io.put_integer (process.exit_code)
            io.put_new_line
        end

feature {NONE} -- Output

    on_stdout (a_chunk: READABLE_STRING_8)
            -- Print standard-output `a_chunk`.
        do
            io.put_string ("OUT: ")
            io.put_string (a_chunk)
        end

    on_stderr (a_chunk: READABLE_STRING_8)
            -- Print standard-error `a_chunk`.
        do
            io.error.put_string ("ERR: ")
            io.error.put_string (a_chunk)
        end

end
