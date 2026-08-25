class
    OS_FILE_PATH_TESTS

create
    make

feature {NONE} -- Initialization

    make
            -- Run the file-path test suite.
        local
            root: OS_FILE_PATH
            exceptions: EXCEPTIONS
        do
            create exceptions
            root := new_test_root
            test_root := root

            test_construction_and_paths (root)
            test_missing_entry (root)
            test_directories_and_files (root)
            test_symbolic_links (root)
            root.delete_recursively
            assert ("recursive delete", not entry_exists (root))
            root.delete_recursively
            assert ("repeated recursive delete", not entry_exists (root))
            test_root := Void

            if failure_count = 0 then
                io.put_string ("All os_file_path tests passed.%N")
            else
                io.error.put_string ("Failures: ")
                io.error.put_integer (failure_count)
                io.error.put_new_line
                exceptions.die (1)
            end
        rescue
            cleanup
        end

feature {NONE} -- Test suite

    test_construction_and_paths (a_root: OS_FILE_PATH)
            -- Construct paths and derive related paths.
        local
            base_path: PATH
            from_string: OS_FILE_PATH
            from_path: OS_FILE_PATH
            nested: OS_FILE_PATH
            canonical: OS_FILE_PATH
            canonical_base: PATH
        do
            create base_path.make_from_string (a_root.name)
            create from_string.make (a_root.name)
            create from_path.make_from_path (base_path)
            assert ("make name", from_string.name.same_string (a_root.name))
            assert ("make_from_path name", from_path.name.same_string (a_root.name))

            nested := (a_root / "one") / "two.txt"
            assert ("extended parent", nested.parent.name.same_string ((a_root / "one").name))

            canonical := ((a_root / "one") / "..").canonical_path
            create canonical_base.make_from_string (canonical.name)
            assert ("canonical path absolute", canonical_base.is_absolute)
            assert ("canonical path normalized", canonical.name.same_string (a_root.canonical_path.name))
        end

    test_missing_entry (a_root: OS_FILE_PATH)
            -- Report stable negative states for an absent entry.
        do
            assert ("missing does not exist", not a_root.exists)
            assert ("missing is not directory", not a_root.is_directory)
            assert ("missing is not plain file", not a_root.is_plain_file)
            assert ("missing is not empty directory", not a_root.is_empty_directory)
            a_root.delete_recursively
            assert ("missing delete is no-op", not entry_exists (a_root))
        end

    test_directories_and_files (a_root: OS_FILE_PATH)
            -- Create directories and round-trip file contents.
        local
            nested_directory: OS_FILE_PATH
            empty_directory: OS_FILE_PATH
            text_file: OS_FILE_PATH
            unicode_file: OS_FILE_PATH
            unicode_name: STRING_32
            unicode_text: STRING_32
            utf_8_text: STRING_8
        do
            a_root.create_directory
            assert ("root directory", a_root.is_directory)
            assert ("new root empty", a_root.is_empty_directory)
            a_root.create_directory
            assert ("repeated directory create", a_root.is_directory)

            nested_directory := (a_root / "nested") / "deep"
            nested_directory.create_directory
            assert ("recursive directory create", nested_directory.is_directory)
            assert ("root no longer empty", not a_root.is_empty_directory)

            empty_directory := a_root / "empty"
            empty_directory.create_directory
            assert ("empty directory", empty_directory.is_empty_directory)

            text_file := nested_directory / "message.txt"
            text_file.write_text ("first")
            assert ("written file exists", text_file.exists)
            assert ("written file is plain", text_file.is_plain_file)
            assert ("written file is not directory", not text_file.is_directory)
            assert ("read text", text_file.read_text.same_string ("first"))
            text_file.write_text ("second")
            assert ("overwrite text", text_file.read_text.same_string ("second"))

            unicode_name := {STRING_32} "данные.txt"
            unicode_text := {STRING_32} "Привет"
            unicode_file := a_root / unicode_name
            unicode_file.write_text (unicode_text)
            utf_8_text := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (unicode_text)
            assert ("unicode file name", unicode_file.exists)
            assert ("utf-8 text", unicode_file.read_text.same_string (utf_8_text))
        end

    test_symbolic_links (a_root: OS_FILE_PATH)
            -- Delete symbolic links without deleting their targets.
        local
            target_directory: OS_FILE_PATH
            target_file: OS_FILE_PATH
            directory_link: OS_FILE_PATH
            missing_target: OS_FILE_PATH
            broken_link: OS_FILE_PATH
            runner: OS_PROCESS_RUNNER
            process_result: OS_PROCESS_RESULT
        do
            if not {PLATFORM}.is_windows then
                target_directory := a_root / "link-target"
                target_directory.create_directory
                target_file := target_directory / "keep.txt"
                target_file.write_text ("keep")
                directory_link := a_root / "directory-link"
                create runner
                process_result := runner.run ("ln", link_arguments (target_directory, directory_link))
                assert ("directory symlink created", process_result.successful and entry_exists (directory_link))
                if process_result.successful then
                    directory_link.delete_recursively
                    assert ("directory symlink removed", not entry_exists (directory_link))
                    assert ("symlink target retained", target_file.exists)
                end

                missing_target := a_root / "missing-target"
                broken_link := a_root / "broken-link"
                process_result := runner.run ("ln", link_arguments (missing_target, broken_link))
                assert ("broken symlink created", process_result.successful and entry_exists (broken_link))
                if process_result.successful then
                    assert ("broken symlink target absent", not broken_link.exists)
                    broken_link.delete_recursively
                    assert ("broken symlink removed", not entry_exists (broken_link))
                end
            end
        end

feature {NONE} -- Support

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
            -- Remove the test tree after an exceptional exit.
        do
            if attached test_root as root then
                root.delete_recursively
                test_root := Void
            end
        end

    assert (a_name: READABLE_STRING_8; a_condition: BOOLEAN)
            -- Record whether named test condition `a_condition` holds.
        do
            if a_condition then
                io.put_string ("PASS: ")
                io.put_string (a_name)
                io.put_new_line
            else
                failure_count := failure_count + 1
                io.error.put_string ("FAIL: ")
                io.error.put_string (a_name)
                io.error.put_new_line
            end
        end

feature {NONE} -- State

    test_root: detachable OS_FILE_PATH

    failure_count: INTEGER

end
