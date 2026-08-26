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

    failure_description: detachable STRING_8
            -- Description of the first failure, if any.
        local
            description: STRING_8
        do
            if read_failed then
                create description.make_from_string ("Cannot read standard ")
                description.append (stream_name)
                if native_error_code > 0 then
                    append_native_error (description, native_error_code)
                end
                Result := description
            elseif callback_failed then
                create description.make_from_string ("Standard-")
                description.append (stream_name)
                description.append (" callback failed")
                Result := description
            end
        ensure
            failure_reported: has_failed = attached Result
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
            retried: BOOLEAN
        do
            if not retried then
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
                        native_error_code := -count
                    end
                end
            end
        rescue
            read_failed := True
            retried := True
            retry
        end

    call_handler (a_chunk: READABLE_STRING_8)
            -- Forward `a_chunk`, recording but containing callback failure.
        local
            retried: BOOLEAN
        do
            if not retried and then not callback_failed and then attached handler as output_handler then
                output_handler.call ([a_chunk])
            end
        rescue
            callback_failed := True
            retried := True
            retry
        end

    stream_name: STRING_8
            -- Name of the stream read by Current.
        do
            if is_stdout then
                Result := "output"
            else
                Result := "error"
            end
        end

    append_native_error (a_message: STRING_8; a_code: INTEGER)
            -- Append native error `a_code` to `a_message`.
        require
            positive_code: a_code > 0
        do
            a_message.append (" (native error ")
            a_message.append_integer (a_code)
            a_message.append_character (')')
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

    native_error_code: INTEGER

    buffer_capacity: INTEGER = 4096

end
