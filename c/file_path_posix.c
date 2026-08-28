#ifndef _WIN32

#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#if defined(__APPLE__) && !defined(_DARWIN_C_SOURCE)
#define _DARWIN_C_SOURCE
#endif

#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

#include "file_path.h"

#include <errno.h>
#include <stdio.h>
#include <sys/stat.h>

#if defined(__linux__)
#include <fcntl.h>
#elif defined(__APPLE__)
#include <sys/stdio.h>
#else
#error "The file-path backend supports only Linux, macOS, and Windows"
#endif

int os_file_path_rename_no_replace(const os_file_path_character *source,
                                   const os_file_path_character *target)
{
    int status;
    if (source == NULL || target == NULL)
        return EINVAL;
    do
    {
#if defined(__linux__)
        status = renameat2(AT_FDCWD, source, AT_FDCWD, target, RENAME_NOREPLACE);
#else
        status = renamex_np(source, target, RENAME_EXCL);
#endif
    } while (status != 0 && errno == EINTR);
    return status == 0 ? 0 : errno;
}

int os_file_path_replace(const os_file_path_character *source,
                         const os_file_path_character *target)
{
    int status;
    if (source == NULL || target == NULL)
        return EINVAL;
    do
    {
        status = rename(source, target);
    } while (status != 0 && errno == EINTR);
    return status == 0 ? 0 : errno;
}

int os_file_path_size(const os_file_path_character *path, uint64_t *size)
{
    struct stat information;
    int status;
    if (path == NULL || size == NULL)
        return EINVAL;
    do
    {
        status = stat(path, &information);
    } while (status != 0 && errno == EINTR);
    if (status != 0)
        return errno;
    if (information.st_size < 0)
        return EOVERFLOW;
    *size = (uint64_t)information.st_size;
    return 0;
}

#endif
