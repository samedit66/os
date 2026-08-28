#ifndef OS_FILE_PATH_H
#define OS_FILE_PATH_H

#include <stdint.h>

#ifdef _WIN32
#include <wchar.h>
typedef wchar_t os_file_path_character;
#else
typedef char os_file_path_character;
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    /*
     * Rename source to an absent target without copying across file systems.
     * Return zero on success or a positive platform error code on failure.
     */
    int os_file_path_rename_no_replace(const os_file_path_character *source,
                                       const os_file_path_character *target);

    /*
     * Rename source over target without copying across file systems.
     * Return zero on success or a positive platform error code on failure.
     */
    int os_file_path_replace(const os_file_path_character *source,
                             const os_file_path_character *target);

    /*
     * Store the byte size of path in size. Return zero on success or a positive
     * platform error code on failure.
     */
    int os_file_path_size(const os_file_path_character *path, uint64_t *size);

#ifdef __cplusplus
}
#endif

#endif
