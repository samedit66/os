note

	description:
	"[
        Value object that denotes a native filesystem path and provides
        convenient whole-file and directory operations.

        File contents and filesystem status are external mutable state.
        Queries such as `text`, `bytes`, and `exists` observe that state
        at the time of the call.

        Example:

        ```eiffel
        local
            file: OS_FILE_PATH
        do
            create file.make ("message.txt")
            file.write_text ("Hello from Eiffel%N")
            io.put_string (file.text)
        end
        ```
    ]"
	author: "samedit66 <samedit66@yandex.ru>"
	library: "os"

frozen class OS_FILE_PATH

create

	make,
	make_from_path

convert

	make ({STRING_8, STRING_32, READABLE_STRING_GENERAL})

feature -- Initialization

	make (a_name: READABLE_STRING_GENERAL)
			-- Create a path represented by `a_name`.
		do
			create path.make_from_string (a_name)
		end

	make_from_path (a_path: PATH)
			-- Create a path based on `a_path`.
		do
			path := a_path
		ensure
			name_set: name.same_string (a_path.name)
		end

feature -- Access

	name: IMMUTABLE_STRING_32
			-- String representation of Current.
		do
			Result := path.name
		end

	parent: OS_FILE_PATH
			-- Parent path of Current.
		do
			create Result.make_from_path (path.parent)
		end

	normalized_absolute_path: OS_FILE_PATH
			-- Absolute path with "." and ".." normalized lexically.
			-- Use the process working directory at the time of the call
			-- for a relative Current; do not resolve symbolic links.
		do
			create Result.make_from_path (path.canonical_path)
		end

feature -- Status report

	exists: BOOLEAN
			-- Does Current denote an existing file-system entry?
		local
			file_info: FILE_INFO
		do
			create file_info.make
			file_info.update (path.name)
			Result := file_info.exists
		end

	is_directory: BOOLEAN
			-- Does Current denote a directory?
		local
			file_info: FILE_INFO
		do
			create file_info.make
			file_info.update (path.name)
			Result := file_info.exists and then file_info.is_directory
		end

	is_plain_file: BOOLEAN
			-- Does Current denote a plain file?
		local
			file_info: FILE_INFO
		do
			create file_info.make
			file_info.update (path.name)
			Result := file_info.exists and then file_info.is_plain
		end

	is_empty_directory: BOOLEAN
			-- Does Current denote a directory without entries?
		local
			directory: DIRECTORY
		do
			if is_directory then
				create directory.make_with_path (path)
				Result := directory.is_empty
			end
		end

feature -- Content access

	bytes: IMMUTABLE_STRING_8
			-- Snapshot of the complete raw contents of Current.
		require
			readable_file: is_plain_file
		local
			buffer: STRING_8
			file: detachable RAW_FILE
		do
			create buffer.make_empty
			create file.make_with_path (path)
			file.open_read
			from
			until
				not file.file_readable
			loop
				file.read_stream (read_buffer_size)
				buffer.append (file.last_string)
			end
			file.close
			create Result.make_from_string (buffer)
		rescue
			if attached file as opened_file and then not opened_file.is_closed then
				opened_file.close
			end
		end

	text: IMMUTABLE_STRING_32
			-- Snapshot of the complete UTF-8 text contents of Current.
			-- Raise a conversion failure if Current is not valid UTF-8.
		require
			readable_file: is_plain_file
		local
			file_bytes: IMMUTABLE_STRING_8
			decoded: STRING_32
		do
			create Result.make_empty
			file_bytes := bytes
			if {UTF_CONVERTER}.is_valid_utf_8_string_8 (file_bytes) then
				decoded := {UTF_CONVERTER}.utf_8_string_8_to_string_32 (file_bytes)
				create Result.make_from_string_32 (decoded)
			else
				raise_conversion_failure (invalid_text_message)
			end
		end

	text_with_encoding (a_encoding: ENCODING): IMMUTABLE_STRING_32
			-- Snapshot of the complete contents of Current decoded using
			-- a snapshot of `a_encoding`.
			-- Raise a conversion failure if the contents cannot be decoded.
		require
			readable_file: is_plain_file
		do
			Result := decoded_text (bytes, a_encoding)
		end

feature -- Basic operations

	create_directory
			-- Create Current as a directory, including missing parents.
			-- Do nothing if Current already denotes a directory.
		require
			not_an_existing_file: not exists or else is_directory
		local
			directory: DIRECTORY
		do
			if not exists then
				create directory.make_with_path (path)
				directory.recursive_create_dir
			end
		ensure
			directory_exists: is_directory
		end

	write_bytes (a_bytes: READABLE_STRING_8)
			-- Write exactly `a_bytes` to Current, replacing existing contents.
		require
			writable_target: not exists or else is_plain_file
		local
			file: detachable RAW_FILE
		do
			create file.make_with_path (path)
			file.open_write
			file.put_string (a_bytes)
			file.close
		ensure
			file_exists: is_plain_file
		rescue
			if attached file as opened_file and then not opened_file.is_closed then
				opened_file.close
			end
		end

	write_text (a_text: READABLE_STRING_GENERAL)
			-- Encode `a_text` as UTF-8 and write it to Current, replacing
			-- existing contents. Do not write a byte-order mark.
		require
			writable_target: not exists or else is_plain_file
		local
			encoded: STRING_8
		do
			encoded := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text)
			write_bytes (encoded)
		ensure
			file_exists: is_plain_file
		end

	write_text_with_encoding (a_text: READABLE_STRING_GENERAL; a_encoding: ENCODING)
			-- Encode `a_text` using a snapshot of `a_encoding` and write it
			-- to Current, replacing existing contents.
			-- Raise a conversion failure without changing Current if
			-- `a_text` cannot be represented in `a_encoding`.
		require
			writable_target: not exists or else is_plain_file
		do
			write_bytes (encoded_text (a_text, a_encoding))
		ensure
			file_exists: is_plain_file
		end

	delete_recursively
			-- Delete Current recursively if it exists.
			-- Delete symbolic links without following them.
		local
			file_info: FILE_INFO
			directory: DIRECTORY
			file: RAW_FILE
		do
			create file_info.make
			file_info.set_is_following_symlinks (False)
			file_info.update (path.name)
			if file_info.exists then
				if file_info.is_directory and then not file_info.is_symlink then
					create directory.make_with_path (path)
					directory.recursive_delete
				else
					create file.make_with_path (path)
					file.delete
				end
			end
		ensure
			removed: not entry_exists
		end

feature -- Path operations

	extended alias "/" (a_name: READABLE_STRING_GENERAL): OS_FILE_PATH
			-- New path obtained by appending `a_name` to Current.
		require
			name_not_empty: not a_name.is_empty
			relative_name: not (create {PATH}.make_from_string (a_name)).has_root
		do
			create Result.make_from_path (path.extended (a_name))
		end

feature {NONE} -- Implementation

	path: PATH
			-- Underlying path.

	entry_exists: BOOLEAN
			-- Does the file-system entry exist without following symbolic links?
		local
			file_info: FILE_INFO
		do
			create file_info.make
			file_info.set_is_following_symlinks (False)
			file_info.update (path.name)
			Result := file_info.exists
		end

	decoded_text (a_bytes: READABLE_STRING_8; a_encoding: ENCODING): IMMUTABLE_STRING_32
			-- `a_bytes` decoded strictly using a snapshot of `a_encoding`.
		local
			code_page: STRING_8
			source_encoding: ENCODING
			target_encoding: ENCODING
			converted_bytes: STRING_8
			converted_text: STRING_32
			index: INTEGER
			conversion_failed: BOOLEAN
			mutex_locked: BOOLEAN
		do
			create Result.make_empty
			create code_page.make_from_string (a_encoding.code_page)
			if code_page.is_case_insensitive_equal ({CODE_PAGE_CONSTANTS}.utf8) then
				if {UTF_CONVERTER}.is_valid_utf_8_string_8 (a_bytes) then
					converted_text := {UTF_CONVERTER}.utf_8_string_8_to_string_32 (a_bytes)
				else
					conversion_failed := True
					create converted_text.make_empty
				end
			elseif is_iso_8859_1_code_page (code_page) then
				create converted_text.make (a_bytes.count)
				from
					index := 1
				until
					index > a_bytes.count
				loop
					converted_text.append_code (a_bytes.code (index))
					index := index + 1
				end
			else
				create source_encoding.make (code_page)
				create target_encoding.make ({CODE_PAGE_CONSTANTS}.utf8)
				encoding_mutex.lock
				mutex_locked := True
				source_encoding.convert_to (target_encoding, a_bytes)
				if source_encoding.last_conversion_successful and then not source_encoding.last_conversion_lost_data then
					converted_bytes := source_encoding.last_converted_stream.twin
					if {UTF_CONVERTER}.is_valid_utf_8_string_8 (converted_bytes) then
						converted_text := {UTF_CONVERTER}.utf_8_string_8_to_string_32 (converted_bytes)
					else
						conversion_failed := True
						create converted_text.make_empty
					end
				else
					conversion_failed := True
					create converted_text.make_empty
				end
				encoding_mutex.unlock
				mutex_locked := False
			end
			if conversion_failed then
				raise_conversion_failure (invalid_text_message)
			else
				create Result.make_from_string_32 (converted_text)
			end
		rescue
			if mutex_locked then
				encoding_mutex.unlock
			end
		end

	encoded_text (a_text: READABLE_STRING_GENERAL; a_encoding: ENCODING): IMMUTABLE_STRING_8
			-- `a_text` encoded strictly using a snapshot of `a_encoding`.
		local
			code_page: STRING_8
			source_encoding: ENCODING
			target_encoding: ENCODING
			utf_8_text: STRING_8
			converted_bytes: STRING_8
			index: INTEGER
			code: NATURAL_32
			conversion_failed: BOOLEAN
			mutex_locked: BOOLEAN
		do
			create Result.make_empty
			create code_page.make_from_string (a_encoding.code_page)
			if code_page.is_case_insensitive_equal ({CODE_PAGE_CONSTANTS}.utf8) then
				converted_bytes := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text)
			elseif is_iso_8859_1_code_page (code_page) then
				create converted_bytes.make (a_text.count)
				from
					index := 1
				until
					index > a_text.count or else conversion_failed
				loop
					code := a_text.code (index)
					if code <= 0xFF then
						converted_bytes.append_code (code)
					else
						conversion_failed := True
					end
					index := index + 1
				end
			else
				utf_8_text := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text)
				create source_encoding.make ({CODE_PAGE_CONSTANTS}.utf8)
				create target_encoding.make (code_page)
				encoding_mutex.lock
				mutex_locked := True
				source_encoding.convert_to (target_encoding, utf_8_text)
				if source_encoding.last_conversion_successful and then not source_encoding.last_conversion_lost_data then
					converted_bytes := source_encoding.last_converted_stream.twin
				else
					conversion_failed := True
					create converted_bytes.make_empty
				end
				encoding_mutex.unlock
				mutex_locked := False
			end
			if conversion_failed then
				raise_conversion_failure (unrepresentable_text_message)
			else
				create Result.make_from_string (converted_bytes)
			end
		rescue
			if mutex_locked then
				encoding_mutex.unlock
			end
		end

	is_iso_8859_1_code_page (a_code_page: READABLE_STRING_8): BOOLEAN
			-- Does `a_code_page` denote ISO-8859-1?
		do
			Result := a_code_page.is_case_insensitive_equal ("ISO-8859-1") or else a_code_page.same_string ("28591")
		end

	raise_conversion_failure (a_message: STRING_8)
			-- Raise a conversion failure described by `a_message`.
		do
			(create {EXCEPTIONS}).raise (a_message)
		end

	encoding_mutex: MUTEX
			-- Process-wide lock protecting stateful encoding converters.
		once
			create Result.make
		end

	read_buffer_size: INTEGER = 4096

	invalid_text_message: STRING_8 = "File contents are not valid in the selected encoding"

	unrepresentable_text_message: STRING_8 = "Text cannot be represented in the selected encoding"

end -- class OS_FILE_PATH
