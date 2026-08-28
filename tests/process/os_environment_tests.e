note

	description:

		"Test cases for environment storage and executable lookup."

	author: "samedit66 <samedit66@yandex.ru>"
	library: "os"

class OS_ENVIRONMENT_TESTS

inherit

	TS_TEST_CASE

create

	make_default

feature -- Test

	test_variable_storage
			-- Copy names, values, and query results without conflating empty and absent values.
		local
			environment: OS_ENVIRONMENT
			variable_name: STRING_32
			value: STRING_32
			value_snapshot: STRING_32
		do
			create environment.make
			environment.clear
			create variable_name.make_from_string_general ("OS_ENVIRONMENT_TEST_VALUE")
			create value.make_from_string_general ("before")
			environment.set_variable (variable_name, value)
			variable_name.wipe_out
			value.wipe_out
			assert_true ("copied name present", environment.has_variable ("OS_ENVIRONMENT_TEST_VALUE"))
			assert_general_strings_equal ("copied value", "before", environment.variable ("OS_ENVIRONMENT_TEST_VALUE"))
			value_snapshot := environment.variable ("OS_ENVIRONMENT_TEST_VALUE")
			value_snapshot.wipe_out
			assert_general_strings_equal ("defensive query", "before", environment.variable ("OS_ENVIRONMENT_TEST_VALUE"))
			environment.set_variable ("OS_ENVIRONMENT_EMPTY", "")
			assert_true ("empty value present", environment.has_variable ("OS_ENVIRONMENT_EMPTY"))
			assert_true ("empty value retained", environment.variable ("OS_ENVIRONMENT_EMPTY").is_empty)
			assert_false ("absent remains distinct", environment.has_variable ("OS_ENVIRONMENT_ABSENT"))
		end

	test_unset_and_clear
			-- Remove one variable or the complete environment.
		local
			environment: OS_ENVIRONMENT
		do
			create environment.make
			environment.clear
			environment.set_variable ("FIRST", "one")
			environment.set_variable ("SECOND", "two")
			environment.unset_variable ("FIRST")
			assert_false ("first removed", environment.has_variable ("FIRST"))
			assert_true ("second retained", environment.has_variable ("SECOND"))
			environment.clear
			assert_false ("second cleared", environment.has_variable ("SECOND"))
		end

	test_prepend_to_path
			-- Prepend directories using the platform PATH separator.
		local
			environment: OS_ENVIRONMENT
			expected: STRING_32
		do
			create environment.make
			environment.clear
			environment.prepend_to_path ("first directory")
			assert_general_strings_equal ("initial path", "first directory", environment.variable ("PATH"))
			environment.prepend_to_path ("second directory")
			create expected.make_from_string_general ("second directory")
			if {PLATFORM}.is_windows then
				expected.append_character (';')
			else
				expected.append_character (':')
			end
			expected.append ("first directory")
			assert_general_strings_equal ("prepended path", expected, environment.variable ("PATH"))
		end

	test_executable_lookup
			-- Resolve an executable from only the configured PATH and by its explicit path.
		local
			environment: OS_ENVIRONMENT
			executable: PATH
			executable_name: PATH
		do
			create executable.make_from_string (process_child_executable)
			executable := executable.canonical_path
			check
				attached executable.entry as entry
			then
				executable_name := entry
			end
			create environment.make
			environment.clear
			assert_false ("bare executable needs path", environment.has_executable (executable_name.name))
			environment.prepend_to_path (executable.parent.name)
			assert_true ("bare executable found", environment.has_executable (executable_name.name))
			assert_general_strings_equal ("resolved executable", executable.name, environment.executable_path (executable_name.name))
			assert_true ("explicit executable found", environment.has_executable (executable.name))
		end

	test_windows_variable_names_are_caseless
			-- Match environment names without case only on Windows.
		local
			environment: OS_ENVIRONMENT
		do
			create environment.make
			environment.clear
			environment.set_variable ("Mixed_Name", "value")
			if {PLATFORM}.is_windows then
				assert_true ("windows caseless name", environment.has_variable ("MIXED_NAME"))
				environment.unset_variable ("mixed_name")
				assert_false ("windows caseless unset", environment.has_variable ("Mixed_Name"))
			else
				assert_false ("unix case-sensitive name", environment.has_variable ("MIXED_NAME"))
			end
		end

feature {NONE} -- Support

	process_child_executable: STRING
			-- Path of the helper executable used for executable lookup.
		do
			if variables.has (process_child_variable) then
				Result := variables.value (process_child_variable)
			else
				assert_true ("process child configured", False)
				create Result.make_empty
			end
		end

	assert_general_strings_equal (a_tag: STRING_8; a_expected, a_actual: READABLE_STRING_GENERAL)
			-- Assert that `a_actual` has the same characters as `a_expected`.
		do
			assert_true (a_tag, a_actual.same_string (a_expected))
		end

feature {NONE} -- Constants

	process_child_variable: STRING = "process_child"

end
