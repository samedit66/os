class
    OS_PROCESS_PIPE_READER

create {OS_PROCESS}
    make

feature {NONE} -- Initialization

    make (
        a_process: POINTER;
        a_is_stdout: BOOLEAN;
        a_handler: detachable PROCEDURE [READABLE_STRING_8]
    )
            -- Create a reader for one pipe of `a_process`.
        require
            process_attached: a_process /= default_pointer
        do
            process := a_process
            is_stdout := a_is_stdout
            handler := a_handler
            create output.make_empty
            create worker.make (agent read_loop)
        end

feature {OS_PROCESS} -- Access

    output: STRING_8
            -- Bytes captured by this reader.

feature {OS_PROCESS} -- Status report

    is_finished: BOOLEAN
            -- Has the reader thread terminated?
        do
            Result := worker.terminated
        end

    has_failed: BOOLEAN
            -- Did a native read or user callback fail?
        do
            Result := read_failed or callback_failed
        end

feature {OS_PROCESS} -- Basic operations

    launch
            -- Launch the Eiffel reader thread.
        do
            worker.launch
        ensure
            launched: worker.is_last_launch_successful
        end

    join
            -- Wait for the reader thread.
        do
            worker.join
        end

feature {NONE} -- Reading

    read_loop
            -- Drain this reader's pipe until EOF.
        local
            area: MANAGED_POINTER
            bytes: C_STRING
            chunk: STRING_8
            count: INTEGER
        do
            create area.make (buffer_capacity)
            from
                count := 1
            until
                count = 0 or read_failed
            loop
                if is_stdout then
                    count := c_read_stdout (process, area.item, area.count)
                else
                    count := c_read_stderr (process, area.item, area.count)
                end
                if count > 0 then
                    create bytes.make_by_pointer_and_count (area.item, count)
                    chunk := bytes.string_8
                    output.append (chunk)
                    call_handler (chunk)
                elseif count < 0 then
                    read_failed := True
                end
            end
        rescue
            read_failed := True
        end

    call_handler (a_chunk: READABLE_STRING_8)
            -- Forward `a_chunk`, recording but containing callback failure.
        do
            if attached handler as output_handler then
                output_handler.call ([a_chunk])
            end
        rescue
            callback_failed := True
        end

feature {NONE} -- Native bridge

    c_read_stdout (a_process, a_buffer: POINTER; a_capacity: INTEGER): INTEGER
        external "C blocking use <subprocess.h>" alias "os_process_read_stdout" end

    c_read_stderr (a_process, a_buffer: POINTER; a_capacity: INTEGER): INTEGER
        external "C blocking use <subprocess.h>" alias "os_process_read_stderr" end

feature {NONE} -- Implementation

    process: POINTER

    is_stdout: BOOLEAN

    handler: detachable PROCEDURE [READABLE_STRING_8]

    worker: WORKER_THREAD

    read_failed: BOOLEAN

    callback_failed: BOOLEAN

    buffer_capacity: INTEGER = 4096

end
