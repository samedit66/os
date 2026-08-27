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
            create failure_mutex.make
            create worker.make (agent read_loop)
        end

feature {OS_PROCESS} -- Access

    output: STRING_8
            -- Bytes captured by this reader after `join`.

    failures: READABLE_INDEXABLE [OS_PROCESS_FAILURE]
            -- Defensive snapshot of failures recorded by this reader.
        local
            snapshot: ARRAYED_LIST [OS_PROCESS_FAILURE]
            read_snapshot: detachable OS_PROCESS_FAILURE
            handler_snapshot: detachable OS_PROCESS_FAILURE
        do
            failure_mutex.lock
            read_snapshot := read_failure
            handler_snapshot := handler_failure
            failure_mutex.unlock
            create snapshot.make (2)
            if attached read_snapshot as failure then
                snapshot.extend (failure)
            end
            if attached handler_snapshot as failure then
                snapshot.extend (failure)
            end
            Result := snapshot
        end

feature {OS_PROCESS} -- Status report

    is_finished: BOOLEAN
            -- Has the reader thread terminated?
        do
            Result := worker.terminated
        end

    is_last_launch_successful: BOOLEAN
            -- Did the most recent worker launch succeed?
        do
            Result := worker.is_last_launch_successful
        end

    has_failed: BOOLEAN
            -- Did a native read or user callback fail?
        do
            failure_mutex.lock
            Result := attached read_failure or attached handler_failure
            failure_mutex.unlock
        end

feature {OS_PROCESS} -- Basic operations

    launch
            -- Attempt to launch the Eiffel reader thread.
        do
            worker.launch
        end

    join
            -- Wait for the launched reader thread.
        require
            launched: is_last_launch_successful
        do
            worker.join
        ensure
            finished: is_finished
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
                    count = 0 or read_has_failed
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
                        record_read_failure (-count)
                    end
                end
            end
        rescue
            record_read_failure (0)
            retried := True
            retry
        end

    call_handler (a_chunk: READABLE_STRING_8)
            -- Forward `a_chunk`, recording and containing callback failure.
        local
            retried: BOOLEAN
        do
            if not retried and then not handler_has_failed and then
                attached handler as output_handler
            then
                output_handler.call ([a_chunk])
            end
        rescue
            record_handler_failure
            retried := True
            retry
        end

    record_read_failure (a_native_code: INTEGER)
            -- Record the first read failure, with `a_native_code` when positive.
        require
            nonnegative_native_code: a_native_code >= 0
        local
            failure_kind: OS_PROCESS_FAILURE_KIND
            new_failure: OS_PROCESS_FAILURE
            operation_name: STRING_8
            message: STRING_8
        do
            if is_stdout then
                create failure_kind.make_stdout_read
                operation_name := "read stdout"
                message := "Cannot read standard output"
            else
                create failure_kind.make_stderr_read
                operation_name := "read stderr"
                message := "Cannot read standard error"
            end
            if a_native_code > 0 then
                create new_failure.make_with_native_code (
                    failure_kind, operation_name, message, a_native_code
                )
            else
                create new_failure.make (failure_kind, operation_name, message)
            end
            failure_mutex.lock
            if not attached read_failure then
                read_failure := new_failure
            end
            failure_mutex.unlock
        end

    record_handler_failure
            -- Record the first exception raised by this stream's handler.
        local
            failure_kind: OS_PROCESS_FAILURE_KIND
            new_failure: OS_PROCESS_FAILURE
            operation_name: STRING_8
            message: STRING_8
        do
            if is_stdout then
                create failure_kind.make_stdout_handler
                operation_name := "handle stdout"
                message := "Standard-output handler failed"
            else
                create failure_kind.make_stderr_handler
                operation_name := "handle stderr"
                message := "Standard-error handler failed"
            end
            create new_failure.make (failure_kind, operation_name, message)
            failure_mutex.lock
            if not attached handler_failure then
                handler_failure := new_failure
            end
            failure_mutex.unlock
        end

    read_has_failed: BOOLEAN
            -- Has reading failed?
        do
            failure_mutex.lock
            Result := attached read_failure
            failure_mutex.unlock
        end

    handler_has_failed: BOOLEAN
            -- Has the callback failed?
        do
            failure_mutex.lock
            Result := attached handler_failure
            failure_mutex.unlock
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

    failure_mutex: MUTEX

    read_failure: detachable OS_PROCESS_FAILURE

    handler_failure: detachable OS_PROCESS_FAILURE

    buffer_capacity: INTEGER = 4096

end
