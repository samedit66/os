#ifdef _WIN32

#include "file_path.h"

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0600
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <limits.h>

static int error_as_int(DWORD error) { return error > INT_MAX ? INT_MAX : (int)error; }

int os_file_path_rename_no_replace(const os_file_path_character *source,
                                   const os_file_path_character *target)
{
    if (source == NULL || target == NULL)
        return ERROR_INVALID_PARAMETER;
    if (MoveFileExW(source, target, 0) != 0)
        return 0;
    return error_as_int(GetLastError());
}

int os_file_path_replace(const os_file_path_character *source, const os_file_path_character *target)
{
    if (source == NULL || target == NULL)
        return ERROR_INVALID_PARAMETER;
    if (MoveFileExW(source, target, MOVEFILE_REPLACE_EXISTING) != 0)
        return 0;
    return error_as_int(GetLastError());
}

int os_file_path_size(const os_file_path_character *path, uint64_t *size)
{
    WIN32_FILE_ATTRIBUTE_DATA information;
    if (path == NULL || size == NULL)
        return ERROR_INVALID_PARAMETER;
    if (GetFileAttributesExW(path, GetFileExInfoStandard, &information) == 0)
        return error_as_int(GetLastError());
    *size = ((uint64_t)information.nFileSizeHigh << 32) | information.nFileSizeLow;
    return 0;
}

#endif
