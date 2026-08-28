note

	description:

		"Internal native operations required by OS_FILE_PATH."

	author: "samedit66 <samedit66@yandex.ru>"
	library: "os"
	warning: "Internal implementation class; client code should use `OS_FILE_PATH`."

class OS_FILE_PATH_NATIVE

feature {OS_FILE_PATH} -- Basic operations

	rename_no_replace (a_source, a_target: PATH)
			-- Rename `a_source` to absent `a_target` without a copy fallback.
		local
			source_name: NATIVE_STRING
			target_name: NATIVE_STRING
			status: INTEGER
		do
			source_name := a_source.native_string
			target_name := a_target.native_string
			status := c_rename_no_replace (source_name.item, target_name.item)
			if status /= 0 then
				raise_native_failure ("Cannot rename file-system entry", status)
			end
		end

	replace (a_source, a_target: PATH)
			-- Rename `a_source` over `a_target` without a copy fallback.
		local
			source_name: NATIVE_STRING
			target_name: NATIVE_STRING
			status: INTEGER
		do
			source_name := a_source.native_string
			target_name := a_target.native_string
			status := c_replace (source_name.item, target_name.item)
			if status /= 0 then
				raise_native_failure ("Cannot replace file-system entry", status)
			end
		end

feature {OS_FILE_PATH} -- Measurement

	file_size (a_path: PATH): NATURAL_64
			-- Size of the plain file at `a_path` in bytes.
		local
			path_name: NATIVE_STRING
			size_area: MANAGED_POINTER
			status: INTEGER
		do
			path_name := a_path.native_string
			create size_area.make ({PLATFORM}.natural_64_bytes)
			status := c_size (path_name.item, size_area.item)
			if status /= 0 then
				raise_native_failure ("Cannot read file size", status)
			else
				Result := size_area.read_natural_64 (0)
			end
		end

feature {NONE} -- Failure

	raise_native_failure (a_operation: READABLE_STRING_8; a_code: INTEGER)
			-- Raise a native failure for `a_operation` with `a_code`.
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

	c_rename_no_replace (a_source, a_target: POINTER): INTEGER
		external
			"C use <file_path.h>"
		alias
			"os_file_path_rename_no_replace"
		end

	c_replace (a_source, a_target: POINTER): INTEGER
		external
			"C use <file_path.h>"
		alias
			"os_file_path_replace"
		end

	c_size (a_path, a_size: POINTER): INTEGER
		external
			"C use <file_path.h>"
		alias
			"os_file_path_size"
		end

end -- class OS_FILE_PATH_NATIVE
