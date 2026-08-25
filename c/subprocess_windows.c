#ifdef _WIN32

#include "subprocess.h"

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0600
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <wchar.h>

struct os_process {
    HANDLE process;
    HANDLE stdout_read;
    HANDLE stderr_read;
    int exit_code;
    int has_exited;
};

typedef struct wide_buffer {
    wchar_t *data;
    size_t count;
    size_t capacity;
} wide_buffer;

static int error_as_int(DWORD error)
{
    return error > INT_MAX ? INT_MAX : (int)error;
}

static wchar_t *utf8_to_wide(const char *text, int *error_code)
{
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, NULL, 0);
    wchar_t *result;
    if (count == 0) {
        *error_code = error_as_int(GetLastError());
        return NULL;
    }
    result = (wchar_t *)calloc((size_t)count, sizeof(wchar_t));
    if (result == NULL) {
        *error_code = ERROR_NOT_ENOUGH_MEMORY;
        return NULL;
    }
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, result, count) == 0) {
        *error_code = error_as_int(GetLastError());
        free(result);
        return NULL;
    }
    return result;
}

static int append_wide(wide_buffer *buffer, wchar_t value)
{
    size_t capacity;
    wchar_t *data;
    if (buffer->count + 2 > buffer->capacity) {
        capacity = buffer->capacity == 0 ? 64 : buffer->capacity * 2;
        data = (wchar_t *)realloc(buffer->data, capacity * sizeof(wchar_t));
        if (data == NULL) return 0;
        buffer->data = data;
        buffer->capacity = capacity;
    }
    buffer->data[buffer->count++] = value;
    buffer->data[buffer->count] = L'\0';
    return 1;
}

static int append_backslashes(wide_buffer *buffer, size_t count)
{
    while (count-- > 0) {
        if (!append_wide(buffer, L'\\')) return 0;
    }
    return 1;
}

static int append_argument(wide_buffer *buffer, const wchar_t *argument)
{
    const wchar_t *cursor;
    size_t backslashes;
    int quoted = argument[0] == L'\0' || wcspbrk(argument, L" \t\n\v\"") != NULL;
    if (!quoted) {
        for (cursor = argument; *cursor != L'\0'; ++cursor) {
            if (!append_wide(buffer, *cursor)) return 0;
        }
        return 1;
    }
    if (!append_wide(buffer, L'\"')) return 0;
    cursor = argument;
    while (*cursor != L'\0') {
        backslashes = 0;
        while (*cursor == L'\\') {
            ++backslashes;
            ++cursor;
        }
        if (*cursor == L'\"') {
            if (!append_backslashes(buffer, backslashes * 2 + 1) ||
                !append_wide(buffer, *cursor++)) return 0;
        } else if (*cursor == L'\0') {
            if (!append_backslashes(buffer, backslashes * 2)) return 0;
        } else {
            if (!append_backslashes(buffer, backslashes) ||
                !append_wide(buffer, *cursor++)) return 0;
        }
    }
    return append_wide(buffer, L'\"');
}

static wchar_t *build_command_line(char *const arguments[], int *error_code)
{
    wide_buffer buffer = {0};
    wchar_t *argument;
    size_t index;
    for (index = 0; arguments[index] != NULL; ++index) {
        argument = utf8_to_wide(arguments[index], error_code);
        if (argument == NULL) {
            free(buffer.data);
            return NULL;
        }
        if ((index > 0 && !append_wide(&buffer, L' ')) ||
            !append_argument(&buffer, argument)) {
            free(argument);
            free(buffer.data);
            *error_code = ERROR_NOT_ENOUGH_MEMORY;
            return NULL;
        }
        free(argument);
    }
    if (buffer.data == NULL) *error_code = ERROR_INVALID_PARAMETER;
    return buffer.data;
}

static void close_handle(HANDLE *handle)
{
    if (*handle != NULL && *handle != INVALID_HANDLE_VALUE) {
        (void)CloseHandle(*handle);
        *handle = NULL;
    }
}

os_process *os_process_start(
    const char *executable,
    char *const arguments[],
    int *error_code
)
{
    SECURITY_ATTRIBUTES security = {sizeof(security), NULL, TRUE};
    HANDLE stdout_read = NULL, stdout_write = NULL;
    HANDLE stderr_read = NULL, stderr_write = NULL;
    HANDLE stdin_read = NULL;
    STARTUPINFOEXW startup = {0};
    PROCESS_INFORMATION information = {0};
    SIZE_T attributes_size = 0;
    HANDLE inherited[3];
    wchar_t *command_line = NULL;
    os_process *process = NULL;
    DWORD windows_error = ERROR_SUCCESS;

    if (error_code == NULL) return NULL;
    *error_code = 0;
    if (executable == NULL || arguments == NULL) {
        *error_code = ERROR_INVALID_PARAMETER;
        return NULL;
    }
    command_line = build_command_line(arguments, error_code);
    if (command_line == NULL) goto fail;
    if (!CreatePipe(&stdout_read, &stdout_write, &security, 0) ||
        !SetHandleInformation(stdout_read, HANDLE_FLAG_INHERIT, 0) ||
        !CreatePipe(&stderr_read, &stderr_write, &security, 0) ||
        !SetHandleInformation(stderr_read, HANDLE_FLAG_INHERIT, 0)) {
        windows_error = GetLastError();
        goto fail;
    }
    stdin_read = CreateFileW(
        L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
        &security, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL
    );
    if (stdin_read == INVALID_HANDLE_VALUE) {
        windows_error = GetLastError();
        goto fail;
    }

    ZeroMemory(&startup, sizeof(startup));
    startup.StartupInfo.cb = sizeof(startup);
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startup.StartupInfo.hStdInput = stdin_read;
    startup.StartupInfo.hStdOutput = stdout_write;
    startup.StartupInfo.hStdError = stderr_write;
    inherited[0] = stdin_read;
    inherited[1] = stdout_write;
    inherited[2] = stderr_write;
    (void)InitializeProcThreadAttributeList(NULL, 1, 0, &attributes_size);
    startup.lpAttributeList = (PPROC_THREAD_ATTRIBUTE_LIST)malloc(attributes_size);
    if (startup.lpAttributeList == NULL) {
        windows_error = ERROR_NOT_ENOUGH_MEMORY;
        goto fail;
    }
    if (!InitializeProcThreadAttributeList(startup.lpAttributeList, 1, 0, &attributes_size) ||
        !UpdateProcThreadAttribute(
            startup.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
            inherited, sizeof(inherited), NULL, NULL
        )) {
        windows_error = GetLastError();
        goto fail;
    }

    ZeroMemory(&information, sizeof(information));
    if (!CreateProcessW(
        NULL, command_line, NULL, NULL, TRUE,
        EXTENDED_STARTUPINFO_PRESENT, NULL, NULL,
        &startup.StartupInfo, &information
    )) {
        windows_error = GetLastError();
        goto fail;
    }
    (void)CloseHandle(information.hThread);
    close_handle(&stdout_write);
    close_handle(&stderr_write);
    close_handle(&stdin_read);
    process = (os_process *)calloc(1, sizeof(*process));
    if (process == NULL) {
        (void)TerminateProcess(information.hProcess, 1);
        (void)WaitForSingleObject(information.hProcess, INFINITE);
        (void)CloseHandle(information.hProcess);
        windows_error = ERROR_NOT_ENOUGH_MEMORY;
        goto fail;
    }
    process->process = information.hProcess;
    process->stdout_read = stdout_read;
    process->stderr_read = stderr_read;
    process->exit_code = -1;
    stdout_read = NULL;
    stderr_read = NULL;

fail:
    if (startup.lpAttributeList != NULL) {
        DeleteProcThreadAttributeList(startup.lpAttributeList);
        free(startup.lpAttributeList);
    }
    free(command_line);
    close_handle(&stdout_read);
    close_handle(&stdout_write);
    close_handle(&stderr_read);
    close_handle(&stderr_write);
    close_handle(&stdin_read);
    if (process == NULL && windows_error != ERROR_SUCCESS) {
        *error_code = error_as_int(windows_error);
    }
    return process;
}

static int read_handle(HANDLE handle, void *buffer, int capacity)
{
    DWORD count = 0;
    DWORD error;
    if (buffer == NULL || capacity <= 0) return -ERROR_INVALID_PARAMETER;
    if (!ReadFile(handle, buffer, (DWORD)capacity, &count, NULL)) {
        error = GetLastError();
        return error == ERROR_BROKEN_PIPE ? 0 : -error_as_int(error);
    }
    return (int)count;
}

int os_process_read_stdout(os_process *process, void *buffer, int capacity)
{
    return process == NULL ? -ERROR_INVALID_PARAMETER :
        read_handle(process->stdout_read, buffer, capacity);
}

int os_process_read_stderr(os_process *process, void *buffer, int capacity)
{
    return process == NULL ? -ERROR_INVALID_PARAMETER :
        read_handle(process->stderr_read, buffer, capacity);
}

static int store_exit_code(os_process *process, int *exit_code)
{
    DWORD native_code;
    if (!GetExitCodeProcess(process->process, &native_code)) return error_as_int(GetLastError());
    process->exit_code = (int)native_code;
    process->has_exited = 1;
    *exit_code = process->exit_code;
    return 0;
}

int os_process_poll(os_process *process, int *finished, int *exit_code)
{
    DWORD result;
    if (process == NULL || finished == NULL || exit_code == NULL) return ERROR_INVALID_PARAMETER;
    if (process->has_exited) {
        *finished = 1;
        *exit_code = process->exit_code;
        return 0;
    }
    result = WaitForSingleObject(process->process, 0);
    if (result == WAIT_TIMEOUT) {
        *finished = 0;
        *exit_code = -1;
        return 0;
    }
    if (result != WAIT_OBJECT_0) return error_as_int(GetLastError());
    *finished = 1;
    return store_exit_code(process, exit_code);
}

int os_process_wait(os_process *process, int *exit_code)
{
    if (process == NULL || exit_code == NULL) return ERROR_INVALID_PARAMETER;
    if (process->has_exited) {
        *exit_code = process->exit_code;
        return 0;
    }
    if (WaitForSingleObject(process->process, INFINITE) != WAIT_OBJECT_0) {
        return error_as_int(GetLastError());
    }
    return store_exit_code(process, exit_code);
}

int os_process_terminate(os_process *process)
{
    if (process == NULL) return ERROR_INVALID_PARAMETER;
    if (process->has_exited) return 0;
    return TerminateProcess(process->process, 1) ? 0 : error_as_int(GetLastError());
}

void os_process_free(os_process *process)
{
    if (process != NULL) {
        close_handle(&process->stdout_read);
        close_handle(&process->stderr_read);
        close_handle(&process->process);
        free(process);
    }
}

int os_process_is_command_error(int error_code)
{
    return error_code == ERROR_FILE_NOT_FOUND ||
        error_code == ERROR_PATH_NOT_FOUND ||
        error_code == ERROR_ACCESS_DENIED ||
        error_code == ERROR_BAD_EXE_FORMAT;
}

#endif
