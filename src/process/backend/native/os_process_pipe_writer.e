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
            create failure_mutex.make
            create worker.make (agent write_loop)
        end

feature {OS_PROCESS} -- Access

    failures: READABLE_INDEXABLE [OS_PROCESS_FAILURE]
            -- Defensive snapshot of failures recorded by this writer.
        local
            snapshot: ARRAYED_LIST [OS_PROCESS_FAILURE]
            write_snapshot: detachable OS_PROCESS_FAILURE
            close_snapshot: detachable OS_PROCESS_FAILURE
        do
            failure_mutex.lock
            write_snapshot := write_failure
            close_snapshot := close_failure
            failure_mutex.unlock
            create snapshot.make (2)
            if attached write_snapshot as failure then
                snapshot.extend (failure)
            end
            if attached close_snapshot as failure then
                snapshot.extend (failure)
            end
            Result := snapshot
        end

feature {OS_PROCESS} -- Status report

    is_finished: BOOLEAN
            -- Has the writer thread terminated?
        do
            Result := worker.terminated
        end

    is_last_launch_successful: BOOLEAN
            -- Did the most recent worker launch succeed?
        do
            Result := worker.is_last_launch_successful
        end

    has_failed: BOOLEAN
            -- Did a native write or close fail?
        do
            failure_mutex.lock
            Result := attached write_failure or attached close_failure
            failure_mutex.unlock
        end

feature {OS_PROCESS} -- Basic operations

    launch
            -- Attempt to launch the Eiffel writer thread.
        do
            worker.launch
        end

    join
            -- Wait for the launched writer thread.
        require
            launched: is_last_launch_successful
        do
            worker.join
        ensure
            finished: is_finished
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
            retried: BOOLEAN
        do
            if not retried then
                create area.make (buffer_capacity)
                from
                    input_index := 1
                until
                    input_index > input.count or write_has_failed
                loop
                    count := buffer_capacity.min (input.count - input_index + 1)
                    from
                        area_index := 0
                    until
                        area_index = count
                    loop
                        area.put_natural_8 (
                            input.code (input_index + area_index).to_natural_8,
                            area_index
                        )
                        area_index := area_index + 1
                    end
                    written := c_write_stdin (process, area.item, count)
                    if written > 0 then
                        input_index := input_index + written
                    elseif written = 0 then
                        input_index := input.count + 1
                    else
                        record_write_failure (-written)
                    end
                end
                close_pipe
            end
        rescue
            record_write_failure (0)
            close_pipe
            retried := True
            retry
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
                    record_close_failure (status)
                end
            end
        end

    record_write_failure (a_native_code: INTEGER)
            -- Record the first write failure, with `a_native_code` when positive.
        require
            nonnegative_native_code: a_native_code >= 0
        local
            failure_kind: OS_PROCESS_FAILURE_KIND
            new_failure: OS_PROCESS_FAILURE
        do
            create failure_kind.make_stdin_write
            if a_native_code > 0 then
                create new_failure.make_with_native_code (
                    failure_kind,
                    "write stdin",
                    "Cannot write standard input",
                    a_native_code
                )
            else
                create new_failure.make (
                    failure_kind,
                    "write stdin",
                    "Cannot write standard input"
                )
            end
            failure_mutex.lock
            if not attached write_failure then
                write_failure := new_failure
            end
            failure_mutex.unlock
        end

    record_close_failure (a_native_code: INTEGER)
            -- Record the first standard-input close failure.
        require
            positive_native_code: a_native_code > 0
        local
            failure_kind: OS_PROCESS_FAILURE_KIND
            new_failure: OS_PROCESS_FAILURE
        do
            create failure_kind.make_stdin_close
            create new_failure.make_with_native_code (
                failure_kind,
                "close stdin",
                "Cannot close standard input",
                a_native_code
            )
            failure_mutex.lock
            if not attached close_failure then
                close_failure := new_failure
            end
            failure_mutex.unlock
        end

    write_has_failed: BOOLEAN
            -- Has writing failed?
        do
            failure_mutex.lock
            Result := attached write_failure
            failure_mutex.unlock
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

    failure_mutex: MUTEX

    write_failure: detachable OS_PROCESS_FAILURE

    close_failure: detachable OS_PROCESS_FAILURE

    is_closed: BOOLEAN

    buffer_capacity: INTEGER = 4096

end
