class
    OS_FILE_PATH_TESTS

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
            canonical: OS_FILE_PATH
            canonical_base: PATH
        do
            root := current_test_root
            create base_path.make_from_string (root.name)
            create from_string.make (root.name)
            create from_path.make_from_path (base_path)
            assert_equal ("make name", root.name, from_string.name)
            assert_equal ("make_from_path name", root.name, from_path.name)

            nested := (root / "one") / "two.txt"
            assert_equal ("extended parent", (root / "one").name, nested.parent.name)

            canonical := ((root / "one") / "..").canonical_path
            create canonical_base.make_from_string (canonical.name)
            assert_true ("canonical path absolute", canonical_base.is_absolute)
            assert_equal ("canonical path normalized", root.canonical_path.name, canonical.name)
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
            assert_false ("missing is not empty directory", root.is_empty_directory)
            root.delete_recursively
            assert_false ("missing delete is no-op", entry_exists (root))
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
            utf_8_text: STRING_8
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
            assert_strings_equal ("read text", "first", text_file.read_text)
            text_file.write_text ("second")
            assert_strings_equal ("overwrite text", "second", text_file.read_text)

            unicode_name := {STRING_32} "данные.txt"
            unicode_text := {STRING_32} "Привет"
            unicode_file := root / unicode_name
            unicode_file.write_text (unicode_text)
            utf_8_text := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (unicode_text)
            assert_true ("unicode file name", unicode_file.exists)
            assert_strings_equal ("utf-8 text", utf_8_text, unicode_file.read_text)
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
            command: OS_COMMAND
            process_result: OS_PROCESS_RESULT
        do
            if not {PLATFORM}.is_windows then
                root := current_test_root
                target_directory := root / "link-target"
                target_directory.create_directory
                target_file := target_directory / "keep.txt"
                target_file.write_text ("keep")
                directory_link := root / "directory-link"
                create command.make ("ln", link_arguments (target_directory, directory_link))
                process_result := command.run
                assert_true ("directory symlink created", process_result.successful and entry_exists (directory_link))
                directory_link.delete_recursively
                assert_false ("directory symlink removed", entry_exists (directory_link))
                assert_true ("symlink target retained", target_file.exists)

                missing_target := root / "missing-target"
                broken_link := root / "broken-link"
                create command.make ("ln", link_arguments (missing_target, broken_link))
                process_result := command.run
                assert_true ("broken symlink created", process_result.successful and entry_exists (broken_link))
                assert_false ("broken symlink target absent", broken_link.exists)
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

    current_test_root: OS_FILE_PATH
            -- Root reserved for the current test.
        require
            test_root_attached: attached test_root
        do
            check attached test_root as root then
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

    link_arguments (a_target, a_link: OS_FILE_PATH): ARRAYED_LIST [READABLE_STRING_GENERAL]
            -- Arguments for creating `a_link` to `a_target` with POSIX `ln`.
        do
            create Result.make (3)
            Result.extend ("-s")
            Result.extend (a_target.name)
            Result.extend (a_link.name)
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
