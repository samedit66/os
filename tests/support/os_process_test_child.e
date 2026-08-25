class
    OS_PROCESS_TEST_CHILD

create
    make

feature {NONE} -- Initialization

    make
            -- Perform the child behavior selected by the command line.
        local
            arguments: ARGUMENTS_32
            exceptions: EXCEPTIONS
        do
            create arguments
            if arguments.argument_count >= 2 and then arguments.argument (1).same_string_general ("--child") then
                run_child (arguments)
            else
                create exceptions
                exceptions.die (2)
            end
        end

feature {NONE} -- Child modes

    run_child (a_arguments: ARGUMENTS_32)
            -- Perform the child behavior selected by argument 2.
        local
            mode: STRING_32
            exceptions: EXCEPTIONS
            environment: EXECUTION_ENVIRONMENT
        do
            create exceptions
            mode := a_arguments.argument (2).to_string_32
            if mode.same_string_general ("arguments") then
                emit_arguments (a_arguments)
            elseif mode.same_string_general ("exit-seven") then
                exceptions.die (7)
            elseif mode.same_string_general ("emit") then
                io.put_string ("stdout-data%N")
                io.error.put_string ("stderr-data%N")
            elseif mode.same_string_general ("large") then
                emit_large_output
            elseif mode.same_string_general ("sleep") then
                create environment
                environment.sleep (10_000_000_000)
            else
                exceptions.die (2)
            end
        end

    emit_arguments (a_arguments: ARGUMENTS_32)
            -- Serialize child arguments without relying on delimiters alone.
        local
            index: INTEGER
            value: STRING_32
        do
            from
                index := 3
            until
                index > a_arguments.argument_count
            loop
                value := a_arguments.argument (index).to_string_32
                io.put_character ('[')
                io.put_integer (value.count)
                io.put_character (']')
                io.put_string (value.to_string_8)
                index := index + 1
            end
        end

    emit_large_output
            -- Write enough bytes to both streams to detect sequential-drain deadlocks.
        local
            stdout_block: STRING_8
            stderr_block: STRING_8
            index: INTEGER
        do
            create stdout_block.make_filled ('o', large_block_size)
            create stderr_block.make_filled ('e', large_block_size)
            from
                index := 1
            until
                index > large_block_count
            loop
                io.put_string (stdout_block)
                io.error.put_string (stderr_block)
                index := index + 1
            end
        end

feature {NONE} -- Constants

    large_block_size: INTEGER = 4096

    large_block_count: INTEGER = 128

end
