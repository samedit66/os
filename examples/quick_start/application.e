note

	description:

		"Demonstrate process execution and file operations with the os library."

	author: "samedit66 <samedit66@yandex.ru>"
	library: "os"

class APPLICATION

create

	make

feature {NONE} -- Initialization

	make
			-- Run the quick-start example.
		local
			command: OS_COMMAND
			process_result: OS_PROCESS_EXECUTION_RESULT
			directory: OS_FILE_PATH
			file: OS_FILE_PATH
		do
			create command.make ("git", <<"--version">>)
			command.set_timeout_milliseconds (5_000)
			command.run
			process_result := command.execution_result
			if process_result.successful then
				io.put_string (process_result.stdout)
			else
				if process_result.stderr_was_captured then
					io.error.put_string (process_result.stderr)
				end
				across
					process_result.failures
				as
					failure
				loop
					io.error.put_string (failure.description)
					io.error.put_new_line
				end
			end
			create directory.make ("build/quick-start")
			directory.create_directory
			file := directory / "message.txt"
			file.write_text ("Hello from os%N")
			io.put_string_32 (file.text)
		end

end
