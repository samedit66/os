class
    OS_FILE_PATH
    -- A class representing a file-system path, which can be a directory or a plain file.

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

    parent: like Current
            -- Parent path of Current.
        do
            create Result.make_from_path (path.parent)
        end

    canonical_path: like Current
            -- Canonical form of Current.
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

feature -- Basic operations

    read_text: STRING_8
            -- Complete byte-oriented text stored in Current.
        require
            readable_file: is_plain_file
        local
            file: detachable PLAIN_TEXT_FILE
        do
            create Result.make_empty
            create file.make_with_path (path)
            file.open_read
            from
            until
                file.end_of_file
            loop
                file.read_stream (4096)
                Result.append (file.last_string)
            end
            file.close
        rescue
            if attached file as opened_file and then not opened_file.is_closed then
                opened_file.close
            end
        end

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

    write_text (a_text: READABLE_STRING_GENERAL)
            -- Write `a_text` to Current, replacing existing contents.
        require
            writable_target: not exists or else is_plain_file
        local
            file: detachable PLAIN_TEXT_FILE
        do
            create file.make_with_path (path)
            file.open_write
            file.put_string_general (a_text)
            file.close
        ensure
            file_exists: is_plain_file
        rescue
            if attached file as opened_file and then not opened_file.is_closed then
                opened_file.close
            end
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

    extended alias "/" (a_name: READABLE_STRING_GENERAL): like Current
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

end -- class OS_FILE_PATH
