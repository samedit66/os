note

	description:

		"Demonstrate streaming command execution with the os library."

	author: "samedit66 <samedit66@yandex.ru>"
	library: "os"

class APPLICATION

create

	make

feature {NONE} -- Initialization

	make
			-- Run a small streaming example.
		local
			command: OS_COMMAND
			process_result: OS_PROCESS_EXECUTION_RESULT
		do
			create command.make ("git", <<"--version">>)
			command.start_streaming (agent on_stdout, agent on_stderr)
			command.wait_for_exit
			process_result := command.execution_result
			if process_result.has_exit_code then
				io.put_string ("Exit code: ")
				io.put_integer (process_result.exit_code)
				io.put_new_line
			else
				across
					process_result.failures
				as
					failure
				loop
					io.error.put_string (failure.description)
					io.error.put_new_line
				end
			end
		end

feature {NONE} -- Output

	on_stdout (a_chunk: READABLE_STRING_8)
			-- Print standard-output `a_chunk`.
		do
			io.put_string ("OUT: ")
			io.put_string (a_chunk)
		end

	on_stderr (a_chunk: READABLE_STRING_8)
			-- Print standard-error `a_chunk`.
		do
			io.error.put_string ("ERR: ")
			io.error.put_string (a_chunk)
		end

end
