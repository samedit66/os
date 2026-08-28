note

	description:

		"Test cases for portable path and whole-file operations."

	author: "samedit66 <samedit66@yandex.ru>"
	library: "os"

class OS_FILE_PATH_TESTS

inherit

	TS_TEST_CASE
		redefine
			set_up,
			tear_down
		end

create

	make_default

feature -- Execution

	set_up
			-- Reserve a unique absent path for one test.
		do
			test_root := new_test_root
		end

	tear_down
			-- Remove the test tree after success or failure.
		do
			cleanup
		end

feature -- Test

	test_construction_and_paths
			-- Construct paths and derive related paths.
		local
			root: OS_FILE_PATH
			base_path: PATH
			from_string: OS_FILE_PATH
			from_path: OS_FILE_PATH
			nested: OS_FILE_PATH
			normalized: OS_FILE_PATH
			normalized_base: PATH
		do
			root := current_test_root
			create base_path.make_from_string (root.name)
			create from_string.make (root.name)
			create from_path.make_from_path (base_path)
			assert_equal ("make name", root.name, from_string.name)
			assert_equal ("make_from_path name", root.name, from_path.name)
			nested := (root / "one") / "two.txt"
			assert_equal ("extended parent", (root / "one").name, nested.parent.name)
			normalized := ((root / "one") / "..").normalized_absolute_path
			create normalized_base.make_from_string (normalized.name)
			assert_true ("normalized path absolute", normalized_base.is_absolute)
			assert_equal ("absolute path normalized", root.normalized_absolute_path.name, normalized.name)
		end

	test_string_conversion
			-- Convert readable strings to paths.
		local
			converted: OS_FILE_PATH
			string_8: STRING_8
			string_32: STRING_32
			general: READABLE_STRING_GENERAL
		do
			converted := "literal/path"
			assert_true ("literal", converted.name.same_string (expected_path_name ("literal/path")))
			string_8 := "eight-bit/path"
			converted := string_8
			assert_true ("string 8", converted.name.same_string (expected_path_name (string_8)))
			string_32 := {STRING_32} "каталог/файл"
			converted := string_32
			assert_true ("string 32", converted.name.same_string (expected_path_name (string_32)))
			general := string_32
			converted := general
			assert_true ("readable string general", converted.name.same_string (expected_path_name (general)))
			assert_true ("argument", path_name ("argument/path").same_string (expected_path_name ("argument/path")))
		end

	test_missing_entry
			-- Report stable negative states for an absent entry.
		local
			root: OS_FILE_PATH
		do
			root := current_test_root
			assert_false ("missing does not exist", root.exists)
			assert_false ("missing is not directory", root.is_directory)
			assert_false ("missing is not plain file", root.is_plain_file)
			assert_false ("missing is not symbolic link", root.is_symbolic_link)
			assert_false ("missing is not empty directory", root.is_empty_directory)
			assert_false ("missing is not executable", root.is_executable)
			root.delete_recursively
			assert_false ("missing delete is no-op", entry_exists (root))
		end

	test_entries_and_metadata
			-- List direct children and report portable file metadata.
		local
			root: OS_FILE_PATH
			text_file: OS_FILE_PATH
			unicode_file: OS_FILE_PATH
			directory_path: OS_FILE_PATH
			late_file: OS_FILE_PATH
			snapshot: ITERABLE [OS_FILE_PATH]
			unicode_name: STRING_32
		do
			root := current_test_root
			root.create_directory
			text_file := root / "message.txt"
			text_file.write_bytes ("four")
			create unicode_name.make (10)
			unicode_name.append_code (0x0434)
			unicode_name.append_code (0x0430)
			unicode_name.append_code (0x043D)
			unicode_name.append_code (0x043D)
			unicode_name.append_code (0x044B)
			unicode_name.append_code (0x0435)
			unicode_name.append_string_general (".txt")
			unicode_file := root / unicode_name
			unicode_file.write_text ("unicode")
			directory_path := root / "nested"
			directory_path.create_directory
			snapshot := root.entries
			late_file := root / "late.txt"
			late_file.write_text ("late")
			assert_integers_equal ("entry snapshot count", 3, iterable_count (snapshot))
			assert_true ("entry has text file", iterable_has_path (snapshot, text_file))
			assert_true ("entry has unicode file", iterable_has_path (snapshot, unicode_file))
			assert_true ("entry has directory", iterable_has_path (snapshot, directory_path))
			assert_false ("entry snapshot excludes later file", iterable_has_path (snapshot, late_file))
			assert_true ("file size", text_file.size = 4)
			text_file.set_executable
			assert_true ("file executable", text_file.is_executable)
		end

	test_copy_rename_and_replace
			-- Copy bytes and use distinct native rename and replacement operations.
		local
			root: OS_FILE_PATH
			source: OS_FILE_PATH
			copied_file: OS_FILE_PATH
			renamed: OS_FILE_PATH
			rename_name: IMMUTABLE_STRING_32
			replacement: OS_FILE_PATH
			target: OS_FILE_PATH
			blocked_source: OS_FILE_PATH
			blocked_target: OS_FILE_PATH
			directory_path: OS_FILE_PATH
			child_file: OS_FILE_PATH
			renamed_directory: OS_FILE_PATH
			raw_bytes: STRING_8
		do
			root := current_test_root
			root.create_directory
			source := root / "source.bin"
			create raw_bytes.make_filled ('x', 4097)
			raw_bytes.put ('%U', 1)
			raw_bytes.put ('%/255/', raw_bytes.count)
			source.write_bytes (raw_bytes)
			copied_file := root / "copy.bin"
			source.copy_to (copied_file)
			assert_bytes_equal ("copy to absent file", raw_bytes, copied_file.bytes)
			copied_file.write_text ("old")
			source.copy_to (copied_file)
			assert_bytes_equal ("copy replaces plain file", raw_bytes, copied_file.bytes)
			assert_bytes_equal ("copy keeps source", raw_bytes, source.bytes)
			assert_exception ("copy rejects same file", agent source.copy_to (source))
			renamed := root / "renamed.bin"
			rename_name := source.name
			source.rename_to (renamed)
			assert_false ("rename removes source", source.exists)
			assert_bytes_equal ("rename keeps bytes", raw_bytes, renamed.bytes)
			assert_equal ("rename keeps value name", rename_name, source.name)
			directory_path := root / "directory"
			directory_path.create_directory
			child_file := directory_path / "child.txt"
			child_file.write_text ("child")
			renamed_directory := root / "renamed-directory"
			directory_path.rename_to (renamed_directory)
			assert_text_equal ("directory rename", "child", (renamed_directory / "child.txt").text)
			target := root / "target.txt"
			target.write_text ("old target")
			replacement := root / "replacement.tmp"
			replacement.write_text ("new target")
			replacement.replace_with (target)
			assert_false ("replace removes source", replacement.exists)
			assert_text_equal ("replace changes target", "new target", target.text)
			blocked_source := root / "blocked-source.txt"
			blocked_source.write_text ("source remains")
			blocked_target := root / "blocked-target.txt"
			blocked_target.write_text ("target remains")
			assert_exception ("rename rejects existing target", agent blocked_source.rename_to (blocked_target))
			assert_text_equal ("failed rename keeps source", "source remains", blocked_source.text)
			assert_text_equal ("failed rename keeps target", "target remains", blocked_target.text)
			assert_exception ("replace rejects directory", agent blocked_source.replace_with (renamed_directory))
		end

	test_posix_links_as_operation_targets
			-- Treat links as entries for replacement and detect hard-link aliases.
		local
			root: OS_FILE_PATH
			original: OS_FILE_PATH
			hard_link: OS_FILE_PATH
			symlink_target: OS_FILE_PATH
			symlink: OS_FILE_PATH
			replacement: OS_FILE_PATH
		do
			if not {PLATFORM}.is_windows then
				root := current_test_root
				root.create_directory
				original := root / "original.txt"
				original.write_text ("original")
				hard_link := root / "hard-link.txt"
				create_hard_link (original, hard_link)
				assert_exception ("copy rejects hard-link alias", agent original.copy_to (hard_link))
				assert_text_equal ("hard-link rejection keeps contents", "original", original.text)
				symlink_target := root / "symlink-target.txt"
				symlink_target.write_text ("keep target")
				symlink := root / "replaceable-link"
				create_symbolic_link (symlink_target, symlink)
				replacement := root / "replacement-link-source.txt"
				replacement.write_text ("replacement")
				replacement.replace_with (symlink)
				assert_false ("replace removes symlink", symlink.is_symbolic_link)
				assert_text_equal ("replace writes link path", "replacement", symlink.text)
				assert_text_equal ("replace keeps link target", "keep target", symlink_target.text)
			end
		end

	test_glob
			-- Match direct child names with the minimal portable wildcard syntax.
		local
			root: OS_FILE_PATH
			alpha: OS_FILE_PATH
			beta: OS_FILE_PATH
			hidden: OS_FILE_PATH
			literal_brackets: OS_FILE_PATH
			unicode_file: OS_FILE_PATH
			directory_path: OS_FILE_PATH
			unicode_name: STRING_32
			unicode_pattern: STRING_32
			matches: ITERABLE [OS_FILE_PATH]
		do
			root := current_test_root
			root.create_directory
			alpha := root / "alpha.txt"
			alpha.write_text ("alpha")
			beta := root / "beta.e"
			beta.write_text ("beta")
			hidden := root / ".hidden"
			hidden.write_text ("hidden")
			literal_brackets := root / "literal[1].txt"
			literal_brackets.write_text ("literal")
			create unicode_name.make (10)
			unicode_name.append_code (0x0434)
			unicode_name.append_code (0x0430)
			unicode_name.append_code (0x043D)
			unicode_name.append_code (0x043D)
			unicode_name.append_code (0x044B)
			unicode_name.append_code (0x0435)
			unicode_name.append_string_general (".txt")
			unicode_file := root / unicode_name
			unicode_file.write_text ("unicode")
			directory_path := root / "nested"
			directory_path.create_directory
			matches := root.glob ("*.txt")
			assert_integers_equal ("direct star match count", 3, iterable_count (matches))
			assert_true ("direct star includes alpha", iterable_has_path (matches, alpha))
			assert_true ("brackets are literal", iterable_has_path (root.glob ("literal[1].txt"), literal_brackets))
			assert_false ("question mark matches one character", iterable_has_path (root.glob ("literal?.txt"), literal_brackets))
			assert_true ("question mark match", iterable_has_path (root.glob ("?eta.e"), beta))
			assert_true ("star includes dot name", iterable_has_path (root.glob ("*"), hidden))
			assert_integers_equal ("star includes every direct entry", 6, iterable_count (root.glob ("*")))
			assert_integers_equal ("case-sensitive glob", 0, iterable_count (root.glob ("*.TXT")))
			assert_integers_equal ("empty pattern", 0, iterable_count (root.glob ("")))
			create unicode_pattern.make (9)
			unicode_pattern.append_code (0x0434)
			unicode_pattern.append_character ('?')
			unicode_pattern.append_code (0x043D)
			unicode_pattern.append_code (0x043D)
			unicode_pattern.append_code (0x044B)
			unicode_pattern.append_code (0x0435)
			unicode_pattern.append_string_general (".*")
			assert_true ("unicode code-point match", iterable_has_path (root.glob (unicode_pattern), unicode_file))
			assert_exception ("slash pattern rejected", agent root.glob ("nested/*.txt"))
			assert_exception ("backslash pattern rejected", agent root.glob ("nested\*.txt"))
		end

	test_glob_recursive
			-- Match descendants iteratively without following nested directory links.
		local
			root: OS_FILE_PATH
			top_file: OS_FILE_PATH
			subdirectory: OS_FILE_PATH
			child_file: OS_FILE_PATH
			nested_directory: OS_FILE_PATH
			deep_file: OS_FILE_PATH
			real_directory: OS_FILE_PATH
			real_file: OS_FILE_PATH
			directory_link: OS_FILE_PATH
			link_child: OS_FILE_PATH
			late_file: OS_FILE_PATH
			snapshot: ITERABLE [OS_FILE_PATH]
		do
			root := current_test_root
			root.create_directory
			top_file := root / "top.txt"
			top_file.write_text ("top")
			subdirectory := root / "sub"
			subdirectory.create_directory
			child_file := subdirectory / "child.txt"
			child_file.write_text ("child")
			nested_directory := subdirectory / "nested"
			nested_directory.create_directory
			deep_file := nested_directory / "deep.txt"
			deep_file.write_text ("deep")
			real_directory := root / "real"
			real_directory.create_directory
			real_file := real_directory / "inside.txt"
			real_file.write_text ("inside")
			if not {PLATFORM}.is_windows then
				directory_link := root / "directory-link"
				create_symbolic_link (real_directory, directory_link)
				link_child := directory_link / "inside.txt"
			end
			snapshot := root.glob_recursive ("*.txt")
			assert_integers_equal ("recursive file count", 4, iterable_count (snapshot))
			assert_true ("recursive includes top", iterable_has_path (snapshot, top_file))
			assert_true ("recursive includes child", iterable_has_path (snapshot, child_file))
			assert_true ("recursive includes deep", iterable_has_path (snapshot, deep_file))
			assert_true ("recursive includes real path", iterable_has_path (snapshot, real_file))
			if not {PLATFORM}.is_windows then
				link_child := (root / "directory-link") / "inside.txt"
				assert_false ("recursive skips nested symlink directory", iterable_has_path (snapshot, link_child))
			end
			assert_true ("recursive includes matching directory", iterable_has_path (root.glob_recursive ("sub"), subdirectory))
			late_file := nested_directory / "late.txt"
			late_file.write_text ("late")
			assert_false ("recursive result is snapshot", iterable_has_path (snapshot, late_file))
		end

	test_directories_and_files
			-- Create directories and round-trip file contents.
		local
			root: OS_FILE_PATH
			nested_directory: OS_FILE_PATH
			empty_directory: OS_FILE_PATH
			text_file: OS_FILE_PATH
			unicode_file: OS_FILE_PATH
			unicode_name: STRING_32
			unicode_text: STRING_32
		do
			root := current_test_root
			root.create_directory
			assert_true ("root directory", root.is_directory)
			assert_true ("new root empty", root.is_empty_directory)
			root.create_directory
			assert_true ("repeated directory create", root.is_directory)
			nested_directory := (root / "nested") / "deep"
			nested_directory.create_directory
			assert_true ("recursive directory create", nested_directory.is_directory)
			assert_false ("root no longer empty", root.is_empty_directory)
			empty_directory := root / "empty"
			empty_directory.create_directory
			assert_true ("empty directory", empty_directory.is_empty_directory)
			text_file := nested_directory / "message.txt"
			text_file.write_text ("first")
			assert_true ("written file exists", text_file.exists)
			assert_true ("written file is plain", text_file.is_plain_file)
			assert_false ("written file is not directory", text_file.is_directory)
			assert_text_equal ("read text", "first", text_file.text)
			text_file.write_text ("second")
			assert_text_equal ("overwrite text", "second", text_file.text)
			unicode_name := {STRING_32} "данные.txt"
			unicode_text := {STRING_32} "Привет"
			unicode_file := root / unicode_name
			unicode_file.write_text (unicode_text)
			assert_true ("unicode file name", unicode_file.exists)
			assert_text_equal ("unicode text", unicode_text, unicode_file.text)
			assert_bytes_equal ("utf-8 bytes", {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (unicode_text), unicode_file.bytes)
		end

	test_binary_contents
			-- Preserve raw bytes across multiple read blocks.
		local
			root: OS_FILE_PATH
			binary_file: OS_FILE_PATH
			raw_bytes: STRING_8
		do
			root := current_test_root
			root.create_directory
			binary_file := root / "binary.dat"
			create raw_bytes.make_filled ('x', 4097)
			raw_bytes.put ('%U', 1)
			raw_bytes.put ('%/128/', 2049)
			raw_bytes.put ('%/255/', 4097)
			binary_file.write_bytes (raw_bytes)
			assert_bytes_equal ("binary round-trip", raw_bytes, binary_file.bytes)
			binary_file.write_bytes ("")
			assert_true ("empty bytes", binary_file.bytes.is_empty)
		end

	test_text_encodings_and_failures
			-- Decode explicit encodings and reject malformed or lossy text.
		local
			root: OS_FILE_PATH
			latin_1_file: OS_FILE_PATH
			invalid_utf_8_file: OS_FILE_PATH
			bom_file: OS_FILE_PATH
			latin_1: ENCODING
			named_latin_1: ENCODING
			numeric_latin_1: ENCODING
			latin_1_text: STRING_32
			unrepresentable_text: STRING_32
			invalid_utf_8: STRING_8
			bom_bytes: STRING_8
			bom_text: IMMUTABLE_STRING_32
		do
			root := current_test_root
			root.create_directory
			latin_1_file := root / "latin-1.txt"
			latin_1 := {SYSTEM_ENCODINGS}.iso_8859_1
			create latin_1_text.make_from_string_general ("caf")
			latin_1_text.append_code (0xE9)
			latin_1_file.write_text_with_encoding (latin_1_text, latin_1)
			create named_latin_1.make ("ISO-8859-1")
			create numeric_latin_1.make ("28591")
			assert_text_equal ("latin-1 text", latin_1_text, latin_1_file.text_with_encoding (latin_1))
			assert_text_equal ("named latin-1 text", latin_1_text, latin_1_file.text_with_encoding (named_latin_1))
			latin_1_file.write_text_with_encoding (latin_1_text, numeric_latin_1)
			assert_text_equal ("numeric latin-1 text", latin_1_text, latin_1_file.text_with_encoding (numeric_latin_1))
			assert_integers_equal ("latin-1 byte count", 4, latin_1_file.bytes.count)
			assert_integers_equal ("latin-1 byte", 233, latin_1_file.bytes.code (latin_1_file.bytes.count).to_integer_32)
			latin_1_file.write_bytes ("before")
			create unrepresentable_text.make (1)
			unrepresentable_text.append_code (0x20AC)
			assert_exception ("unrepresentable text rejected", agent latin_1_file.write_text_with_encoding (unrepresentable_text, latin_1))
			assert_bytes_equal ("failed encoding preserves file", "before", latin_1_file.bytes)
			invalid_utf_8_file := root / "invalid-utf-8.txt"
			create invalid_utf_8.make (2)
			invalid_utf_8.extend ('%/195/')
			invalid_utf_8.extend ('(')
			invalid_utf_8_file.write_bytes (invalid_utf_8)
			assert_exception ("invalid UTF-8 rejected", agent invalid_utf_8_file.text)
			bom_file := root / "bom.txt"
			create bom_bytes.make (6)
			bom_bytes.extend ('%/239/')
			bom_bytes.extend ('%/187/')
			bom_bytes.extend ('%/191/')
			bom_bytes.append ("bom")
			bom_file.write_bytes (bom_bytes)
			bom_text := bom_file.text
			assert_integers_equal ("BOM text count", 4, bom_text.count)
			assert_true ("BOM preserved", bom_text.code (1) = 0xFEFF)
		end

	test_parallel_text_conversion
			-- Keep stateful encoding results isolated across threads.
		local
			root: OS_FILE_PATH
			first_file: OS_FILE_PATH
			second_file: OS_FILE_PATH
			latin_1: ENCODING
			first_text: STRING_32
			second_text: STRING_32
			first_reader: OS_FILE_PATH_ENCODING_READER
			second_reader: OS_FILE_PATH_ENCODING_READER
		do
			root := current_test_root
			root.create_directory
			first_file := root / "first-latin-1.txt"
			second_file := root / "second-latin-1.txt"
			latin_1 := {SYSTEM_ENCODINGS}.iso_8859_1
			create first_text.make_from_string_general ("first-")
			first_text.append_code (0xE9)
			create second_text.make_from_string_general ("second-")
			second_text.append_code (0xF1)
			first_file.write_text_with_encoding (first_text, latin_1)
			second_file.write_text_with_encoding (second_text, latin_1)
			create first_reader.make (first_file, latin_1, first_text)
			create second_reader.make (second_file, latin_1, second_text)
			first_reader.launch
			second_reader.launch
			first_reader.join
			second_reader.join
			assert_true ("first parallel reader", first_reader.successful)
			assert_true ("second parallel reader", second_reader.successful)
		end

	test_symbolic_links
			-- Delete symbolic links without deleting their targets.
		local
			root: OS_FILE_PATH
			target_directory: OS_FILE_PATH
			target_file: OS_FILE_PATH
			directory_link: OS_FILE_PATH
			missing_target: OS_FILE_PATH
			broken_link: OS_FILE_PATH
		do
			if not {PLATFORM}.is_windows then
				root := current_test_root
				target_directory := root / "link target's"
				target_directory.create_directory
				target_file := target_directory / "keep.txt"
				target_file.write_text ("keep")
				directory_link := root / "directory link's"
				create_symbolic_link (target_directory, directory_link)
				assert_true ("directory symlink created", entry_exists (directory_link))
				assert_true ("directory symlink classified", directory_link.is_symbolic_link)
				assert_integers_equal ("directory symlink entries", 1, iterable_count (directory_link.entries))
				assert_integers_equal ("directory symlink recursive root", 1, iterable_count (directory_link.glob_recursive ("*.txt")))
				directory_link.delete_recursively
				assert_false ("directory symlink removed", entry_exists (directory_link))
				assert_true ("symlink target retained", target_file.exists)
				missing_target := root / "missing target's"
				broken_link := root / "broken link's"
				create_symbolic_link (missing_target, broken_link)
				assert_true ("broken symlink created", entry_exists (broken_link))
				assert_false ("broken symlink target absent", broken_link.exists)
				assert_true ("broken symlink classified", broken_link.is_symbolic_link)
				broken_link.rename_to (root / "renamed broken link's")
				broken_link := root / "renamed broken link's"
				assert_true ("broken symlink renamed", broken_link.is_symbolic_link)
				broken_link.delete_recursively
				assert_false ("broken symlink removed", entry_exists (broken_link))
			end
		end

	test_recursive_delete
			-- Delete a tree and tolerate a repeated deletion.
		local
			root: OS_FILE_PATH
			text_file: OS_FILE_PATH
		do
			root := current_test_root
			root.create_directory
			text_file := root / "message.txt"
			text_file.write_text ("delete me")
			root.delete_recursively
			assert_false ("recursive delete", entry_exists (root))
			root.delete_recursively
			assert_false ("repeated recursive delete", entry_exists (root))
		end

feature {NONE} -- Support

	path_name (a_path: OS_FILE_PATH): IMMUTABLE_STRING_32
			-- Name of `a_path`.
		do
			Result := a_path.name
		end

	expected_path_name (a_name: READABLE_STRING_GENERAL): IMMUTABLE_STRING_32
			-- Native path representation of `a_name`.
		local
			a_path: PATH
		do
			create a_path.make_from_string (a_name)
			Result := a_path.name
		end

	assert_bytes_equal (a_tag: STRING_8; a_expected, a_actual: READABLE_STRING_8)
			-- Assert that `a_actual` contains the expected bytes.
		do
			assert_true (a_tag, a_actual.same_string (a_expected))
		end

	assert_text_equal (a_tag: STRING_8; a_expected, a_actual: READABLE_STRING_GENERAL)
			-- Assert that `a_actual` contains the expected text.
		do
			assert_true (a_tag, a_actual.same_string (a_expected))
		end

	iterable_count (a_paths: ITERABLE [OS_FILE_PATH]): INTEGER
			-- Number of paths in `a_paths`.
		do
			across a_paths as path_cursor loop
				Result := Result + 1
			end
		end

	iterable_has_path (a_paths: ITERABLE [OS_FILE_PATH]; a_expected: OS_FILE_PATH): BOOLEAN
			-- Does `a_paths` contain a path named like `a_expected`?
		do
			across a_paths as path_cursor until Result loop
				Result := path_cursor.name.same_string (a_expected.name)
			end
		end

	current_test_root: OS_FILE_PATH
			-- Root reserved for the current test.
		require
			test_root_attached: attached test_root
		do
			check
				attached test_root as root
			then
				Result := root
			end
		end

	new_test_root: OS_FILE_PATH
			-- Unique absent path reserved for this test run.
		local
			temporary_file: PLAIN_TEXT_FILE
			prefix: READABLE_STRING_GENERAL
			root_path: PATH
		do
			if attached {EXECUTION_ENVIRONMENT}.temporary_directory_path as temporary_directory then
				prefix := temporary_directory.extended ("os-file-path-tests-").name
			else
				prefix := "os-file-path-tests-"
			end
			create temporary_file.make_open_temporary_with_prefix (prefix)
			root_path := temporary_file.path
			temporary_file.close
			temporary_file.delete
			create Result.make_from_path (root_path)
		ensure
			absent: not entry_exists (Result)
		end

	create_symbolic_link (a_target, a_link: OS_FILE_PATH)
			-- Create POSIX symbolic link `a_link` to `a_target`.
		require
			supported_platform: not {PLATFORM}.is_windows
		local
			command: STRING_32
			environment: EXECUTION_ENVIRONMENT
		do
			create command.make_from_string_general ("ln -s ")
			command.append (posix_shell_argument (a_target.name))
			command.append_character (' ')
			command.append (posix_shell_argument (a_link.name))
			create environment
			environment.system (command)
			check
				command_succeeded: environment.return_code = 0
			then
			end
		ensure
			link_exists: entry_exists (a_link)
		end

	create_hard_link (a_target, a_link: OS_FILE_PATH)
			-- Create POSIX hard link `a_link` to `a_target`.
		require
			supported_platform: not {PLATFORM}.is_windows
		local
			command: STRING_32
			environment: EXECUTION_ENVIRONMENT
		do
			create command.make_from_string_general ("ln ")
			command.append (posix_shell_argument (a_target.name))
			command.append_character (' ')
			command.append (posix_shell_argument (a_link.name))
			create environment
			environment.system (command)
			check
				command_succeeded: environment.return_code = 0
			then
			end
		ensure
			link_exists: entry_exists (a_link)
		end

	posix_shell_argument (a_argument: READABLE_STRING_GENERAL): STRING_32
			-- Single-quoted POSIX shell representation of `a_argument`.
		local
			index: INTEGER
		do
			create Result.make (a_argument.count + 2)
			Result.append_character ('%'')
			from
				index := 1
			until
				index > a_argument.count
			loop
				if a_argument.item (index) = '%'' then
					Result.append_character ('%'')
					Result.append_character ('\')
					Result.append_character ('%'')
					Result.append_character ('%'')
				else
					Result.append_code (a_argument.code (index))
				end
				index := index + 1
			end
			Result.append_character ('%'')
		end

	entry_exists (a_path: OS_FILE_PATH): BOOLEAN
			-- Does `a_path` exist without following symbolic links?
		local
			file_info: FILE_INFO
		do
			create file_info.make
			file_info.set_is_following_symlinks (False)
			file_info.update (a_path.name)
			Result := file_info.exists
		end

	cleanup
			-- Remove the test tree if one has been reserved.
		do
			if attached test_root as root then
				root.delete_recursively
				test_root := Void
			end
		ensure
			test_root_detached: test_root = Void
		end

feature {NONE} -- State

	test_root: detachable OS_FILE_PATH

end
