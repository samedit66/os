note

	description:

		"Test worker that invokes one command lifecycle operation."

	author: "samedit66 <samedit66@yandex.ru>"
	library: "os"

class OS_COMMAND_LIFECYCLE_CALLER

inherit

	THREAD
		rename
			make as make_thread
		end

create

	make_start,
	make_poll,
	make_wait,
	make_terminate

feature {NONE} -- Initialization

	make_start (a_command: OS_COMMAND)
			-- Prepare one start call on `a_command`.
		do
			command := a_command
			operation := start_operation
			make_thread
		end

	make_poll (a_command: OS_COMMAND)
			-- Prepare one polling call on `a_command`.
		do
			command := a_command
			operation := poll_operation
			make_thread
		end

	make_wait (a_command: OS_COMMAND)
			-- Prepare one waiting call on `a_command`.
		do
			command := a_command
			operation := wait_operation
			make_thread
		end

	make_terminate (a_command: OS_COMMAND)
			-- Prepare one termination call on `a_command`.
		do
			command := a_command
			operation := terminate_operation
			make_thread
		end

feature -- Status report

	successful: BOOLEAN
			-- Did the lifecycle call return normally?

feature {NONE} -- Execution

	execute
			-- Invoke the selected lifecycle operation.
		local
			retried: BOOLEAN
		do
			if retried then
				successful := False
			else
				if operation = start_operation then
					command.start
				elseif operation = poll_operation then
					command.poll
				elseif operation = wait_operation then
					command.wait_for_exit
				else
					command.terminate
				end
				successful := True
			end
		rescue
			retried := True
			retry
		end

feature {NONE} -- Implementation

	command: OS_COMMAND
			-- Shared command under test.

	operation: INTEGER
			-- Selected lifecycle operation.

	start_operation: INTEGER = 1

	poll_operation: INTEGER = 2

	wait_operation: INTEGER = 3

	terminate_operation: INTEGER = 4

invariant

	valid_operation: operation = start_operation or operation = poll_operation or operation = wait_operation or operation = terminate_operation

end
