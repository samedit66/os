class
    OS_PROCESS_HANDLE

create {OS_PROCESS_RUNNER}
    make

feature {NONE} -- Initialization

    make (
        a_executable: READABLE_STRING_GENERAL;
        a_arguments: ITERABLE [READABLE_STRING_GENERAL];
        a_stdout: detachable PROCEDURE [READABLE_STRING_8];
        a_stderr: detachable PROCEDURE [READABLE_STRING_8]
    )
            -- Launch the native process and its two Eiffel readers.
        local
            executable_c: C_STRING
            argument_strings: ARRAYED_LIST [C_STRING]
            argument_vector: MANAGED_POINTER
            error_area: MANAGED_POINTER
            out_reader: OS_PROCESS_PIPE_READER
            err_reader: OS_PROCESS_PIPE_READER
            offset: INTEGER
        do
            exit_code := -1
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

            create error_area.make ({PLATFORM}.integer_32_bytes)
            native_handle := c_start (executable_c.item, argument_vector.item, error_area.item)
            if native_handle = default_pointer then
                if c_is_command_error (error_area.read_integer_32 (0)) then
                    exit_code := command_launch_failure
                    finished := True
                else
                    raise_native_failure ("Cannot start process", error_area.read_integer_32 (0))
                end
            else
                create out_reader.make (native_handle, True, a_stdout)
                create err_reader.make (native_handle, False, a_stderr)
                stdout_reader := out_reader
                stderr_reader := err_reader
                out_reader.launch
                err_reader.launch
            end
        end

feature -- Access

    exit_code: INTEGER
            -- Child exit code; -1 while running.

    stdout: STRING_8
            -- Captured standard-output bytes.
        do
            if attached stdout_reader as reader and then finished then
                Result := reader.output.to_string_8
            else
                Result := stdout_snapshot.to_string_8
            end
        end

    stderr: STRING_8
            -- Captured standard-error bytes.
        do
            if attached stderr_reader as reader and then finished then
                Result := reader.output.to_string_8
            else
                Result := stderr_snapshot.to_string_8
            end
        end

feature -- Status report

    is_finished: BOOLEAN
            -- Has the child completed?
            -- Polling may reap an exited native child and cache its status.
        local
            finished_area: MANAGED_POINTER
            exit_area: MANAGED_POINTER
            status: INTEGER
        do
            if finished then
                Result := True
            elseif native_handle /= default_pointer then
                create finished_area.make ({PLATFORM}.integer_32_bytes)
                create exit_area.make ({PLATFORM}.integer_32_bytes)
                status := c_poll (native_handle, finished_area.item, exit_area.item)
                if status /= 0 then
                    raise_native_failure ("Cannot poll process", status)
                elseif finished_area.read_integer_32 (0) /= 0 then
                    exit_code := exit_area.read_integer_32 (0)
                    process_exited := True
                    Result := True
                end
            end
        end

feature -- Basic operations

    wait
            -- Wait for the child and both pipe readers.
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
                    exit_code := exit_area.read_integer_32 (0)
                    process_exited := True
                end
                if attached stdout_reader as out_reader then
                    out_reader.join
                    stdout_snapshot := out_reader.output.to_string_8
                end
                if attached stderr_reader as err_reader then
                    err_reader.join
                    stderr_snapshot := err_reader.output.to_string_8
                end
                c_free (native_handle)
                native_handle := default_pointer
                finished := True
            end
            if attached stdout_reader as out_reader and then out_reader.has_failed then
                raise_reader_failure
            elseif attached stderr_reader as err_reader and then err_reader.has_failed then
                raise_reader_failure
            end
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

feature {NONE} -- Conversion

    utf_8 (a_text: READABLE_STRING_GENERAL): STRING_8
            -- UTF-8 representation of `a_text`.
        do
            Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text)
        end

feature {NONE} -- Error handling

    raise_reader_failure
            -- Report a read or callback failure after draining both streams.
        do
            (create {EXCEPTIONS}).raise ("A process pipe reader failed")
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

    c_start (a_executable, a_arguments, a_error: POINTER): POINTER
        external "C use <subprocess.h>" alias "os_process_start" end

    c_poll (a_process, a_finished, a_exit_code: POINTER): INTEGER
        external "C use <subprocess.h>" alias "os_process_poll" end

    c_wait (a_process, a_exit_code: POINTER): INTEGER
        external "C use <subprocess.h>" alias "os_process_wait" end

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

    stdout_snapshot: STRING_8

    stderr_snapshot: STRING_8

    process_exited: BOOLEAN

    finished: BOOLEAN

    command_launch_failure: INTEGER = 127

end
