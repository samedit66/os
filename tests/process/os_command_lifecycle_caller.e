note

	description:

		"Test worker that invokes one command lifecycle or configuration operation."

	author: "samedit66 <samedit66@yandex.ru>"
	library: "os"

class OS_COMMAND_LIFECYCLE_CALLER

inherit

	THREAD
		rename
			make as make_thread
		end

create

	make_wait,
	make_terminate,
	make_set_environment

feature {NONE} -- Initialization

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

	make_set_environment (a_command: OS_COMMAND)
			-- Prepare one forbidden environment change on active `a_command`.
		do
			command := a_command
			operation := set_environment_operation
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
				if operation = wait_operation then
					command.wait_for_exit
				elseif operation = terminate_operation then
					command.terminate
				else
					command.set_environment_variable ("OS_PROCESS_ACTIVE_CHANGE", "forbidden")
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

	wait_operation: INTEGER = 3

	terminate_operation: INTEGER = 4

	set_environment_operation: INTEGER = 5

invariant

	valid_operation: operation = wait_operation or operation = terminate_operation or operation = set_environment_operation

end
