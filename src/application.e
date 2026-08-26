class
    APPLICATION

create
    make

feature {NONE} -- Initialization

    make
            -- Run a small streaming example.
        local
            command: OS_COMMAND
            process: OS_PROCESS
            process_result: OS_PROCESS_RESULT
        do
            create command.make ("git", << "--version" >>)
            process := command.start_with_handlers (
                agent on_stdout,
                agent on_stderr
            )
            process.wait
            process_result := process.outcome

            io.put_string ("Exit code: ")
            io.put_integer (process_result.exit_code)
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
