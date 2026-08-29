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
	make_set_environment,
	make_successful_query,
	make_exit_code_query,
	make_stdout_query,
	make_stderr_query

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

	make_successful_query (a_command: OS_COMMAND)
			-- Prepare one `successful` query on `a_command`.
		do
			command := a_command
			operation := successful_query_operation
			make_thread
		end

	make_exit_code_query (a_command: OS_COMMAND)
			-- Prepare one `exit_code` query on `a_command`.
		do
			command := a_command
			operation := exit_code_query_operation
			make_thread
		end

	make_stdout_query (a_command: OS_COMMAND)
			-- Prepare one `stdout` query on `a_command`.
		do
			command := a_command
			operation := stdout_query_operation
			make_thread
		end

	make_stderr_query (a_command: OS_COMMAND)
			-- Prepare one `stderr` query on `a_command`.
		do
			command := a_command
			operation := stderr_query_operation
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
				elseif operation = set_environment_operation then
					command.set_environment_variable ("OS_PROCESS_ACTIVE_CHANGE", "forbidden")
				elseif operation = successful_query_operation then
					ignored_boolean := command.successful
				elseif operation = exit_code_query_operation then
					ignored_integer := command.exit_code
				elseif operation = stdout_query_operation then
					ignored_output := command.stdout
				else
					ignored_output := command.stderr
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

	successful_query_operation: INTEGER = 6

	exit_code_query_operation: INTEGER = 7

	stdout_query_operation: INTEGER = 8

	stderr_query_operation: INTEGER = 9

	ignored_boolean: BOOLEAN
			-- Result retained only to evaluate a Boolean query.

	ignored_integer: INTEGER
			-- Result retained only to evaluate an integer query.

	ignored_output: detachable READABLE_STRING_8
			-- Result retained only to evaluate an output query.

invariant

	valid_operation: operation >= wait_operation and operation <= stderr_query_operation

end
