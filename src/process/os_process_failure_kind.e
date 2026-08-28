note

	description:

		"Value object that identifies a portable process-failure category."

	author: "samedit66 <samedit66@yandex.ru>"
	library: "os"

class OS_PROCESS_FAILURE_KIND

create {OS_PROCESS, OS_PROCESS_PIPE_READER, OS_PROCESS_PIPE_WRITER}

	make_launch,
	make_stdin_write,
	make_stdin_close,
	make_stdout_read,
	make_stderr_read,
	make_stdout_handler,
	make_stderr_handler,
	make_wait,
	make_termination,
	make_worker_initialization

feature {NONE} -- Initialization

	make_launch
			-- Select a process-launch failure.
		do
			code := launch_code
		ensure
			launch: is_launch
		end

	make_stdin_write
			-- Select a standard-input write failure.
		do
			code := stdin_write_code
		ensure
			stdin_write: is_stdin_write
		end

	make_stdin_close
			-- Select a standard-input close failure.
		do
			code := stdin_close_code
		ensure
			stdin_close: is_stdin_close
		end

	make_stdout_read
			-- Select a standard-output read failure.
		do
			code := stdout_read_code
		ensure
			stdout_read: is_stdout_read
		end

	make_stderr_read
			-- Select a standard-error read failure.
		do
			code := stderr_read_code
		ensure
			stderr_read: is_stderr_read
		end

	make_stdout_handler
			-- Select a standard-output handler failure.
		do
			code := stdout_handler_code
		ensure
			stdout_handler: is_stdout_handler
		end

	make_stderr_handler
			-- Select a standard-error handler failure.
		do
			code := stderr_handler_code
		ensure
			stderr_handler: is_stderr_handler
		end

	make_wait
			-- Select a waiting failure.
		do
			code := wait_code
		ensure
			wait: is_wait
		end

	make_termination
			-- Select a termination failure.
		do
			code := termination_code
		ensure
			termination: is_termination
		end

	make_worker_initialization
			-- Select an I/O-worker initialization failure.
		do
			code := worker_initialization_code
		ensure
			worker_initialization: is_worker_initialization
		end

feature -- Status report

	is_launch: BOOLEAN
			-- Is this a process-launch failure?
		do
			Result := code = launch_code
		end

	is_stdin_write: BOOLEAN
			-- Is this a standard-input write failure?
		do
			Result := code = stdin_write_code
		end

	is_stdin_close: BOOLEAN
			-- Is this a standard-input close failure?
		do
			Result := code = stdin_close_code
		end

	is_stdout_read: BOOLEAN
			-- Is this a standard-output read failure?
		do
			Result := code = stdout_read_code
		end

	is_stderr_read: BOOLEAN
			-- Is this a standard-error read failure?
		do
			Result := code = stderr_read_code
		end

	is_stdout_handler: BOOLEAN
			-- Is this a standard-output handler failure?
		do
			Result := code = stdout_handler_code
		end

	is_stderr_handler: BOOLEAN
			-- Is this a standard-error handler failure?
		do
			Result := code = stderr_handler_code
		end

	is_wait: BOOLEAN
			-- Is this a waiting failure?
		do
			Result := code = wait_code
		end

	is_termination: BOOLEAN
			-- Is this a termination failure?
		do
			Result := code = termination_code
		end

	is_worker_initialization: BOOLEAN
			-- Is this an I/O-worker initialization failure?
		do
			Result := code = worker_initialization_code
		end

	same_category (other: OS_PROCESS_FAILURE_KIND): BOOLEAN
			-- Does `other` denote the same portable failure category?
		do
			Result := code = other.code
		end

feature {OS_PROCESS_FAILURE_KIND} -- Implementation

	code: INTEGER
			-- Internal category code.

feature {NONE} -- Constants

	launch_code, stdin_write_code, stdin_close_code, stdout_read_code, stderr_read_code, stdout_handler_code, stderr_handler_code, wait_code, termination_code, worker_initialization_code: INTEGER = unique

invariant

	known_category: is_launch or is_stdin_write or is_stdin_close or is_stdout_read or is_stderr_read or is_stdout_handler or is_stderr_handler or is_wait or is_termination or is_worker_initialization

end
