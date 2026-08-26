class
    OS_PROCESS_PIPE_WRITER

create {OS_PROCESS}
    make

feature {NONE} -- Initialization

    make (a_process: POINTER; a_input: READABLE_STRING_8)
            -- Create a writer for the standard-input pipe of `a_process`.
        require
            process_attached: a_process /= default_pointer
        do
            process := a_process
            create input.make_from_string (a_input)
            create worker.make (agent write_loop)
        end

feature {OS_PROCESS} -- Status report

    is_finished: BOOLEAN
            -- Has the writer thread terminated?
        do
            Result := worker.terminated
        end

    has_failed: BOOLEAN
            -- Did a native write or close fail?
        do
            Result := write_failed
        end

feature {OS_PROCESS} -- Basic operations

    launch
            -- Launch the Eiffel writer thread.
        do
            worker.launch
        ensure
            launched: worker.is_last_launch_successful
        end

    join
            -- Wait for the writer thread.
        do
            worker.join
        end

feature {NONE} -- Writing

    write_loop
            -- Write all input bytes and then close the pipe to signal EOF.
        local
            area: MANAGED_POINTER
            input_index: INTEGER
            area_index: INTEGER
            count: INTEGER
            written: INTEGER
        do
            create area.make (buffer_capacity)
            from
                input_index := 1
            until
                input_index > input.count or write_failed
            loop
                count := buffer_capacity.min (input.count - input_index + 1)
                from
                    area_index := 0
                until
                    area_index = count
                loop
                    area.put_natural_8 (input.code (input_index + area_index).to_natural_8, area_index)
                    area_index := area_index + 1
                end
                written := c_write_stdin (process, area.item, count)
                if written > 0 then
                    input_index := input_index + written
                elseif written = 0 then
                    input_index := input.count + 1
                else
                    write_failed := True
                end
            end
            close_pipe
        rescue
            write_failed := True
            close_pipe
        end

    close_pipe
            -- Close the native input endpoint once.
        local
            status: INTEGER
        do
            if not is_closed then
                status := c_close_stdin (process)
                is_closed := True
                if status /= 0 then
                    write_failed := True
                end
            end
        end

feature {NONE} -- Native bridge

    c_write_stdin (a_process, a_buffer: POINTER; a_capacity: INTEGER): INTEGER
        external "C blocking use <subprocess.h>" alias "os_process_write_stdin" end

    c_close_stdin (a_process: POINTER): INTEGER
        external "C use <subprocess.h>" alias "os_process_close_stdin" end

feature {NONE} -- Implementation

    process: POINTER

    input: STRING_8

    worker: WORKER_THREAD

    write_failed: BOOLEAN

    is_closed: BOOLEAN

    buffer_capacity: INTEGER = 4096

end
