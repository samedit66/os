class
    OS_PROCESS

create {OS_COMMAND}
    make

feature {NONE} -- Initialization

    make (
        a_executable: READABLE_STRING_GENERAL;
        a_arguments: ITERABLE [READABLE_STRING_GENERAL];
        a_stdout: detachable PROCEDURE [READABLE_STRING_8];
        a_stderr: detachable PROCEDURE [READABLE_STRING_8];
        a_working_directory: detachable READABLE_STRING_GENERAL;
        a_input: READABLE_STRING_8
    )
            -- Launch the native process and its Eiffel pipe workers.
        local
            executable_c: C_STRING
            argument_strings: ARRAYED_LIST [C_STRING]
            argument_vector: MANAGED_POINTER
            error_area: MANAGED_POINTER
            working_directory_c: detachable C_STRING
            out_reader: OS_PROCESS_PIPE_READER
            err_reader: OS_PROCESS_PIPE_READER
            in_writer: OS_PROCESS_PIPE_WRITER
            working_directory_pointer: POINTER
            offset: INTEGER
        do
            create stdout_snapshot.make_empty
            create stderr_snapshot.make_empty
            create executable_c.make (utf_8 (a_executable))
            create argument_strings.make (8)
            argument_strings.extend (executable_c)
            across a_arguments as argument loop
                argument_strings.extend (create {C_STRING}.make (utf_8 (argument)))
            end

            create argument_vector.make ((argument_strings.count + 1) * {PLATFORM}.pointer_bytes)
            across argument_strings as argument loop
                argument_vector.put_pointer (argument.item, offset)
                offset := offset + {PLATFORM}.pointer_bytes
            end
            argument_vector.put_pointer (default_pointer, offset)

            if attached a_working_directory as directory then
                create working_directory_c.make (utf_8 (directory))
                working_directory_pointer := working_directory_c.item
            end
            create error_area.make ({PLATFORM}.integer_32_bytes)
            native_handle := c_start (
                executable_c.item,
                argument_vector.item,
                working_directory_pointer,
                error_area.item
            )
            if native_handle = default_pointer then
                if c_is_command_error (error_area.read_integer_32 (0)) then
                    exit_status := command_launch_failure
                    process_exited := True
                    complete
                else
                    raise_native_failure ("Cannot start process", error_area.read_integer_32 (0))
                end
            else
                create out_reader.make (native_handle, True, a_stdout)
                create err_reader.make (native_handle, False, a_stderr)
                create in_writer.make (native_handle, a_input)
                stdout_reader := out_reader
                stderr_reader := err_reader
                stdin_writer := in_writer
                out_reader.launch
                err_reader.launch
                in_writer.launch
            end
        ensure
            missing_process_has_result: native_handle = default_pointer implies is_finished
        end

feature -- Access

    outcome: OS_PROCESS_RESULT
            -- Completed execution outcome.
        require
            finished: is_finished
        do
            check attached process_result as completed_outcome then
                Result := completed_outcome
            end
        end

feature -- Status report

    is_finished: BOOLEAN
            -- Is execution complete and its result available?
        do
            if not finished then
                poll_process
                if process_exited and then io_finished then
                    complete
                end
            end
            Result := finished
        ensure
            result_available: Result implies attached process_result
        end

feature -- Basic operations

    wait
            -- Wait for execution and output collection to complete.
        local
            exit_area: MANAGED_POINTER
            status: INTEGER
        do
            if not finished then
                if not process_exited then
                    create exit_area.make ({PLATFORM}.integer_32_bytes)
                    status := c_wait (native_handle, exit_area.item)
                    if status /= 0 then
                        raise_native_failure ("Cannot wait for process", status)
                    end
                    exit_status := exit_area.read_integer_32 (0)
                    process_exited := True
                end
                join_workers
                complete
            end
            report_io_failure
        ensure
            finished: is_finished
        end

    terminate
            -- Request platform-dependent child termination.
        local
            status: INTEGER
        do
            if not is_finished and then native_handle /= default_pointer then
                status := c_terminate (native_handle)
                if status /= 0 then
                    raise_native_failure ("Cannot terminate process", status)
                end
            end
        end

feature {NONE} -- Completion

    poll_process
            -- Poll the child and retain its status when it has exited.
        local
            finished_area: MANAGED_POINTER
            exit_area: MANAGED_POINTER
            status: INTEGER
        do
            if not process_exited and then native_handle /= default_pointer then
                create finished_area.make ({PLATFORM}.integer_32_bytes)
                create exit_area.make ({PLATFORM}.integer_32_bytes)
                status := c_poll (native_handle, finished_area.item, exit_area.item)
                if status /= 0 then
                    raise_native_failure ("Cannot poll process", status)
                elseif finished_area.read_integer_32 (0) /= 0 then
                    exit_status := exit_area.read_integer_32 (0)
                    process_exited := True
                end
            end
        end

    io_finished: BOOLEAN
            -- Have all standard-I/O workers finished?
        do
            Result :=
                (not attached stdout_reader as out_reader or else out_reader.is_finished) and then
                (not attached stderr_reader as err_reader or else err_reader.is_finished) and then
                (not attached stdin_writer as in_writer or else in_writer.is_finished)
        end

    join_workers
            -- Wait for both output readers and the input writer.
        do
            if attached stdout_reader as out_reader then
                out_reader.join
            end
            if attached stderr_reader as err_reader then
                err_reader.join
            end
            if attached stdin_writer as in_writer then
                in_writer.join
            end
        ensure
            finished: io_finished
        end

    complete
            -- Capture the completed outcome and release the native process.
        require
            process_exited: process_exited
            io_finished: io_finished
        do
            if not finished then
                if attached stdout_reader as out_reader then
                    stdout_snapshot := out_reader.output.to_string_8
                end
                if attached stderr_reader as err_reader then
                    stderr_snapshot := err_reader.output.to_string_8
                end
                if native_handle /= default_pointer then
                    c_free (native_handle)
                    native_handle := default_pointer
                end
                create process_result.make (exit_status, stdout_snapshot, stderr_snapshot)
                finished := True
            end
        ensure
            finished: finished
            result_available: attached process_result
            handle_released: native_handle = default_pointer
        end

feature {NONE} -- Conversion

    utf_8 (a_text: READABLE_STRING_GENERAL): STRING_8
            -- UTF-8 representation of `a_text`.
        do
            Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text)
        end

feature {NONE} -- Error handling

    report_io_failure
            -- Report an I/O or callback failure after joining all workers.
        do
            if attached stdout_reader as out_reader and then out_reader.has_failed then
                raise_pipe_failure
            elseif attached stderr_reader as err_reader and then err_reader.has_failed then
                raise_pipe_failure
            elseif attached stdin_writer as in_writer and then in_writer.has_failed then
                raise_pipe_failure
            end
        end

    raise_pipe_failure
            -- Report a process pipe worker failure.
        do
            (create {EXCEPTIONS}).raise ("A process pipe worker failed")
        end

    raise_native_failure (a_operation: READABLE_STRING_8; a_code: INTEGER)
            -- Report native failure `a_code` for `a_operation`.
        local
            message: STRING_8
        do
            create message.make_from_string (a_operation)
            message.append (" (native error ")
            message.append_integer (a_code)
            message.append_character (')')
            (create {EXCEPTIONS}).raise (message)
        end

feature {NONE} -- Native bridge

    c_start (a_executable, a_arguments, a_working_directory, a_error: POINTER): POINTER
        external "C use <subprocess.h>" alias "os_process_start" end

    c_poll (a_process, a_finished, a_exit_code: POINTER): INTEGER
        external "C use <subprocess.h>" alias "os_process_poll" end

    c_wait (a_process, a_exit_code: POINTER): INTEGER
        external "C blocking use <subprocess.h>" alias "os_process_wait" end

    c_terminate (a_process: POINTER): INTEGER
        external "C use <subprocess.h>" alias "os_process_terminate" end

    c_free (a_process: POINTER)
        external "C use <subprocess.h>" alias "os_process_free" end

    c_is_command_error (a_error: INTEGER): BOOLEAN
        external "C use <subprocess.h>" alias "os_process_is_command_error" end

feature {NONE} -- Implementation

    native_handle: POINTER

    stdout_reader: detachable OS_PROCESS_PIPE_READER

    stderr_reader: detachable OS_PROCESS_PIPE_READER

    stdin_writer: detachable OS_PROCESS_PIPE_WRITER

    stdout_snapshot: STRING_8

    stderr_snapshot: STRING_8

    process_result: detachable OS_PROCESS_RESULT

    exit_status: INTEGER

    process_exited: BOOLEAN

    finished: BOOLEAN

    command_launch_failure: INTEGER = 127

end
