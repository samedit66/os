note
    description: "Test worker that repeatedly reads a file using one encoding."
    author: "samedit66 <samedit66@yandex.ru>"
    library: "os"

class
    OS_FILE_PATH_ENCODING_READER

inherit
    THREAD
        rename
            make as make_thread
        end

create
    make

feature {NONE} -- Initialization

    make (
        a_file: OS_FILE_PATH;
        a_encoding: ENCODING;
        a_expected_text: READABLE_STRING_GENERAL
    )
            -- Prepare to read `a_file` repeatedly using `a_encoding`.
        do
            file := a_file
            encoding := a_encoding
            create expected_text.make_from_string_general (a_expected_text)
            make_thread
        end

feature -- Access

    successful: BOOLEAN
            -- Did every read return the expected text?

feature {NONE} -- Execution

    execute
            -- Read and compare Current's file repeatedly.
        local
            iteration: INTEGER
        do
            successful := True
            from
                iteration := 1
            until
                iteration > iteration_count or else not successful
            loop
                successful := file.text_with_encoding (encoding).same_string (expected_text)
                iteration := iteration + 1
            end
        rescue
            successful := False
        end

feature {NONE} -- Implementation

    file: OS_FILE_PATH

    encoding: ENCODING

    expected_text: IMMUTABLE_STRING_32

    iteration_count: INTEGER = 100

end -- class OS_FILE_PATH_ENCODING_READER
