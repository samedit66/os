note

	description:
	"[
        Mutable snapshot of environment variables and executable lookup rules.

        Variable names are case-sensitive on Unix and case-insensitive on
        Windows. Executable lookup uses ':' to separate PATH entries on Unix
        and ';' on Windows. Unix candidates must be plain files executable by
        the current process. Windows candidates must be plain files; a missing
        extension is resolved by also trying the `.exe` suffix.

        Current does not synchronize concurrent changes. `OS_COMMAND` owns a
        private instance and serializes access through its command mutex.
    ]"
	author: "samedit66 <samedit66@yandex.ru>"
	library: "os"

class OS_ENVIRONMENT

create

	make

feature {NONE} -- Initialization

	make
			-- Snapshot the current process environment.
			-- On Windows, platform-private entries whose names start with '='
			-- are not exposed or passed to child processes.
		local
			entry_pointer: POINTER
			entry_c: C_STRING
			entry_text: STRING_32
			error_area: MANAGED_POINTER
			separator_index: INTEGER
			index: INTEGER
			error_code: INTEGER
		do
			if {PLATFORM}.is_windows then
				create variables.make_caseless (40)
			else
				create variables.make (40)
			end
			create error_area.make ({PLATFORM}.integer_32_bytes)
			from
				entry_pointer := c_environment_entry (index, error_area.item)
			until
				entry_pointer = default_pointer
			loop
				create entry_c.own_from_pointer (entry_pointer)
				entry_text := {UTF_CONVERTER}.utf_8_string_8_to_string_32 (entry_c.string)
				separator_index := entry_text.index_of ('=', 1)
				if separator_index > 1 then
					set_variable (entry_text.substring (1, separator_index - 1), entry_text.substring (separator_index + 1, entry_text.count))
				end
				index := index + 1
				entry_pointer := c_environment_entry (index, error_area.item)
			end
			error_code := error_area.read_integer_32 (0)
			if error_code /= 0 then
				raise_snapshot_failure (error_code)
			end
		end

feature -- Access

	variable (a_name: READABLE_STRING_GENERAL): STRING_32
			-- Copied value of variable `a_name`.
			-- Name matching is case-sensitive on Unix and case-insensitive on Windows.
		require
			valid_name: valid_variable_name (a_name)
			variable_exists: has_variable (a_name)
		do
			check
				attached variables [a_name] as stored_value
			then
				create Result.make_from_string_general (stored_value)
			end
		ensure
			value_preserved: attached variables [a_name] as stored_value and then Result.same_string_general (stored_value)
		end

	executable_path (a_name: READABLE_STRING_GENERAL): STRING_32
			-- Absolute normalized path of executable `a_name` in the current directory context.
			-- A name containing a platform directory separator is checked directly.
			-- Otherwise PATH is searched in order. Unix requires execute permission;
			-- Windows accepts a plain file and also tries `.exe` when no extension
			-- was supplied. No parent PATH fallback is used when PATH is absent.
		require
			valid_name: valid_executable_name (a_name)
			executable_exists: has_executable (a_name)
		local
			current_directory: PATH
		do
			current_directory := {EXECUTION_ENVIRONMENT}.current_working_path
			check
				attached resolved_executable_in (a_name, current_directory) as resolved
			then
				Result := resolved
			end
		ensure
			absolute: (create {PATH}.make_from_string (Result)).is_absolute
		end

feature -- Status report

	has_variable (a_name: READABLE_STRING_GENERAL): BOOLEAN
			-- Is variable `a_name` present?
			-- Name matching is case-sensitive on Unix and case-insensitive on Windows.
		require
			valid_name: valid_variable_name (a_name)
		do
			Result := variables.has (a_name)
		end

	has_executable (a_name: READABLE_STRING_GENERAL): BOOLEAN
			-- Does `a_name` resolve to an executable in the current directory context?
			-- See `executable_path` for Unix and Windows lookup differences.
		require
			valid_name: valid_executable_name (a_name)
		do
			Result := attached resolved_executable_in (a_name, {EXECUTION_ENVIRONMENT}.current_working_path)
		end

	valid_variable_name (a_name: READABLE_STRING_GENERAL): BOOLEAN
			-- May `a_name` identify a portable environment variable?
			-- Windows has private names beginning with '='; they are deliberately
			-- excluded together with '=' in ordinary variable names on all platforms.
		do
			Result := not a_name.is_empty and then not a_name.has_code (0) and then not a_name.has ('=')
		end

	valid_variable_value (a_value: READABLE_STRING_GENERAL): BOOLEAN
			-- May `a_value` be stored in a native environment block?
		do
			Result := not a_value.has_code (0)
		end

	valid_executable_name (a_name: READABLE_STRING_GENERAL): BOOLEAN
			-- May `a_name` identify an executable?
		do
			Result := not a_name.is_empty and then not a_name.has_code (0)
		end

feature -- Change

	set_variable (a_name, a_value: READABLE_STRING_GENERAL)
			-- Set variable `a_name` to a copied `a_value`.
			-- On Windows, differently cased spellings replace the same variable;
			-- on Unix, they denote distinct variables.
		require
			valid_name: valid_variable_name (a_name)
			valid_value: valid_variable_value (a_value)
		local
			name_copy: STRING_32
			value_copy: STRING_32
		do
			create name_copy.make_from_string_general (a_name)
			create value_copy.make_from_string_general (a_value)
			variables.force (value_copy, name_copy)
		ensure
			variable_set: has_variable (a_name)
			value_set: variable (a_name).same_string_general (a_value)
		end

	unset_variable (a_name: READABLE_STRING_GENERAL)
			-- Remove variable `a_name` if present.
			-- Name matching is case-sensitive on Unix and case-insensitive on Windows.
		require
			valid_name: valid_variable_name (a_name)
		do
			variables.remove (a_name)
		ensure
			variable_absent: not has_variable (a_name)
		end

	clear
			-- Remove every inherited and explicitly set variable.
			-- The resulting native environment is empty on Unix and Windows;
			-- no PATH or Windows SYSTEMROOT value is injected by this class.
		do
			variables.wipe_out
		ensure
			empty: variables.is_empty
		end

	prepend_to_path (a_directory: READABLE_STRING_GENERAL)
			-- Prepend copied `a_directory` to PATH.
			-- Use ':' on Unix and ';' on Windows. If PATH is absent or empty,
			-- set it to `a_directory` without adding an empty entry, because an
			-- empty PATH entry conventionally denotes the current directory.
		require
			directory_not_empty: not a_directory.is_empty
			directory_has_no_nul: not a_directory.has_code (0)
		local
			new_path: STRING_32
		do
			create new_path.make_from_string_general (a_directory)
			if has_variable (path_variable) and then not variable (path_variable).is_empty then
				new_path.append_character (path_separator)
				new_path.append (variable (path_variable))
			end
			set_variable (path_variable, new_path)
		ensure
			path_present: has_variable (path_variable)
			path_starts_with_directory: variable (path_variable).starts_with_general (a_directory)
		end

feature {OS_COMMAND} -- Command integration

	has_executable_in (a_name: READABLE_STRING_GENERAL; a_working_directory: PATH): BOOLEAN
			-- Does `a_name` resolve relative to `a_working_directory` when needed?
			-- Relative PATH entries use the command working directory on both Unix
			-- and Windows rather than the current directory of the parent process.
		require
			valid_name: valid_executable_name (a_name)
			working_directory_absolute: a_working_directory.is_absolute
		do
			Result := attached resolved_executable_in (a_name, a_working_directory)
		end

	executable_path_in (a_name: READABLE_STRING_GENERAL; a_working_directory: PATH): STRING_32
			-- Absolute normalized path of `a_name` in `a_working_directory` context.
			-- See `executable_path` for Unix and Windows lookup differences.
		require
			valid_name: valid_executable_name (a_name)
			working_directory_absolute: a_working_directory.is_absolute
			executable_exists: has_executable_in (a_name, a_working_directory)
		do
			check
				attached resolved_executable_in (a_name, a_working_directory) as resolved
			then
				Result := resolved
			end
		end

	entries: ARRAYED_LIST [STRING_32]
			-- Copied NAME=VALUE entries for one native process launch.
			-- POSIX consumes a null-terminated UTF-8 pointer vector. Windows
			-- converts the same entries to a sorted UTF-16 double-NUL block.
		local
			entry: STRING_32
		do
			create Result.make (variables.count)
			from
				variables.start
			until
				variables.after
			loop
				create entry.make (variables.key_for_iteration.count + variables.item_for_iteration.count + 1)
				entry.append_string_general (variables.key_for_iteration)
				entry.append_character ('=')
				entry.append (variables.item_for_iteration)
				Result.extend (entry)
				variables.forth
			end
		ensure
			count_preserved: Result.count = variables.count
		end

feature {NONE} -- Executable lookup

	resolved_executable_in (a_name: READABLE_STRING_GENERAL; a_working_directory: PATH): detachable STRING_32
			-- Absolute normalized executable path for `a_name`, if one exists.
		local
			path_value: STRING_32
			entry_start: INTEGER
			entry_end: INTEGER
			directory_name: STRING_32
		do
			if has_directory_separator (a_name) then
				Result := executable_candidate (create {PATH}.make_from_string (a_name), a_working_directory)
			elseif has_variable (path_variable) then
				path_value := variable (path_variable)
				from
					entry_start := 1
				until
					entry_start > path_value.count or else attached Result
				loop
					entry_end := path_value.index_of (path_separator, entry_start)
					if entry_end = 0 then
						entry_end := path_value.count + 1
					end
					if entry_end > entry_start then
						directory_name := path_value.substring (entry_start, entry_end - 1)
						Result := executable_in_directory (a_name, directory_name, a_working_directory)
					end
					entry_start := entry_end + 1
				end
			end
		end

	executable_in_directory (a_name: READABLE_STRING_GENERAL; a_directory: READABLE_STRING_GENERAL; a_working_directory: PATH): detachable STRING_32
			-- Executable `a_name` in `a_directory`, if present.
		local
			directory_path: PATH
			candidate: PATH
		do
			create directory_path.make_from_string (a_directory)
			directory_path := directory_path.absolute_path_in (a_working_directory).canonical_path
			candidate := directory_path.extended (a_name)
			Result := executable_candidate (candidate, a_working_directory)
		end

	executable_candidate (a_candidate, a_working_directory: PATH): detachable STRING_32
			-- Absolute path of `a_candidate` if it satisfies platform executable rules.
			-- Unix checks the effective execute permission. Windows has no
			-- corresponding permission bit and accepts a plain file, trying `.exe`
			-- after an extensionless candidate.
		local
			absolute_candidate: PATH
		do
			absolute_candidate := a_candidate.absolute_path_in (a_working_directory).canonical_path
			if is_executable_file (absolute_candidate) then
				Result := absolute_candidate.name.to_string_32
			elseif {PLATFORM}.is_windows and then not attached absolute_candidate.extension then
				absolute_candidate := absolute_candidate.appended_with_extension ("exe")
				if is_executable_file (absolute_candidate) then
					Result := absolute_candidate.name.to_string_32
				end
			end
		end

	is_executable_file (a_path: PATH): BOOLEAN
			-- Is `a_path` a directly launchable plain file?
			-- Unix requires execute permission; Windows treats every plain file as
			-- executable at this layer and leaves image validation to CreateProcessW.
		local
			file_info: FILE_INFO
		do
			create file_info.make
			file_info.update (a_path.name)
			Result := file_info.exists and then file_info.is_plain and then ({PLATFORM}.is_windows or else file_info.is_executable)
		end

	has_directory_separator (a_name: READABLE_STRING_GENERAL): BOOLEAN
			-- Does `a_name` contain a platform directory separator or Windows drive root?
		do
			Result := a_name.has ('/') or else ({PLATFORM}.is_windows and then (a_name.has ('\') or else (a_name.count >= 2 and then a_name.item (2) = ':')))
		end

feature {NONE} -- Constants

	path_variable: STRING_32
			-- Platform spelling used when a new PATH variable is inserted.
		once
			create Result.make_from_string_general ("PATH")
		end

	path_separator: CHARACTER_32
			-- Separator between executable search directories.
			-- Unix uses ':'; Windows uses ';'.
		do
			if {PLATFORM}.is_windows then
				Result := ';'
			else
				Result := ':'
			end
		end

feature {NONE} -- Implementation

	variables: STRING_TABLE [STRING_32]
			-- Owned variable values indexed by owned names.

	raise_snapshot_failure (a_code: INTEGER)
			-- Report failure to copy the native process environment.
		local
			message: STRING_8
		do
			create message.make_from_string ("Cannot snapshot process environment (native error ")
			message.append_integer (a_code)
			message.append_character (')')
			(create {EXCEPTIONS}).raise (message)
		end

	c_environment_entry (a_index: INTEGER; a_error: POINTER): POINTER
		external
			"C use <subprocess.h>"
		alias
			"os_environment_entry"
		end

invariant

	variable_names_valid: across variables as stored all valid_variable_name (@ stored.key) end
	variable_values_valid: across variables as stored all valid_variable_value (stored) end
	windows_keys_caseless: {PLATFORM}.is_windows implies variables.is_case_insensitive
	unix_keys_case_sensitive: not {PLATFORM}.is_windows implies not variables.is_case_insensitive

end
