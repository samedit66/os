note

	description:
	"[
        Immutable description of one process-library failure, with a portable
        category and an optional native error code.
    ]"
	author: "samedit66 <samedit66@yandex.ru>"
	library: "os"

class OS_PROCESS_FAILURE

create {OS_PROCESS, OS_PROCESS_PIPE_READER, OS_PROCESS_PIPE_WRITER}

	make,
	make_with_native_code

feature {NONE} -- Initialization

	make (a_kind: OS_PROCESS_FAILURE_KIND; a_operation: READABLE_STRING_8; a_description: READABLE_STRING_8)
			-- Create a failure without a native error code.
		do
			kind := a_kind
			create operation_storage.make_from_string (a_operation)
			create description_storage.make_from_string (a_description)
		ensure
			kind_set: kind = a_kind
			operation_copied: operation.same_string (a_operation)
			description_copied: description.same_string (a_description)
			no_native_code: not has_native_code
		end

	make_with_native_code (a_kind: OS_PROCESS_FAILURE_KIND; a_operation: READABLE_STRING_8; a_description: READABLE_STRING_8; a_native_code: INTEGER)
			-- Create a failure with native error code `a_native_code`.
		require
			positive_native_code: a_native_code > 0
		do
			make (a_kind, a_operation, a_description)
			has_native_code := True
			native_code_storage := a_native_code
		ensure
			kind_set: kind = a_kind
			operation_copied: operation.same_string (a_operation)
			description_copied: description.same_string (a_description)
			has_native_code: has_native_code
			native_code_set: native_code = a_native_code
		end

feature -- Access

	kind: OS_PROCESS_FAILURE_KIND
			-- Portable failure category.

	operation: READABLE_STRING_8
			-- Operation that failed.
		do
			Result := operation_storage
		end

	description: READABLE_STRING_8
			-- Human-readable failure description.
		do
			Result := description_storage
		end

	native_code: INTEGER
			-- Platform error code.
		require
			has_native_code: has_native_code
		do
			Result := native_code_storage
		end

feature -- Status report

	has_native_code: BOOLEAN
			-- Is a platform error code available?

feature {NONE} -- Implementation

	operation_storage: IMMUTABLE_STRING_8
			-- Immutable operation snapshot.

	description_storage: IMMUTABLE_STRING_8
			-- Immutable description snapshot.

	native_code_storage: INTEGER
			-- Stored platform error code, when available.

invariant

	native_code_consistent: has_native_code implies native_code_storage > 0

end
