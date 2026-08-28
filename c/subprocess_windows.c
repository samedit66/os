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
#include <string.h>
#include <wchar.h>

struct os_process
{
    HANDLE process;
    HANDLE job;
    HANDLE stdin_write;
    HANDLE stdout_read;
    HANDLE stderr_read;
    ULONGLONG started_at;
    int exit_code;
    int has_exited;
};

typedef struct wide_buffer
{
    wchar_t *data;
    size_t count;
    size_t capacity;
} wide_buffer;

static int error_as_int(DWORD error) { return error > INT_MAX ? INT_MAX : (int)error; }

static wchar_t *utf8_to_wide(const char *text, int *error_code)
{
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, NULL, 0);
    wchar_t *result;
    if (count == 0)
    {
        *error_code = error_as_int(GetLastError());
        return NULL;
    }
    result = (wchar_t *)calloc((size_t)count, sizeof(wchar_t));
    if (result == NULL)
    {
        *error_code = ERROR_NOT_ENOUGH_MEMORY;
        return NULL;
    }
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, result, count) == 0)
    {
        *error_code = error_as_int(GetLastError());
        free(result);
        return NULL;
    }
    return result;
}

static char *wide_to_utf8(const wchar_t *text, int *error_code)
{
    int count = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text, -1, NULL, 0, NULL, NULL);
    char *result;
    if (count == 0)
    {
        *error_code = error_as_int(GetLastError());
        return NULL;
    }
    result = (char *)malloc((size_t)count);
    if (result == NULL)
    {
        *error_code = ERROR_NOT_ENOUGH_MEMORY;
        return NULL;
    }
    if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text, -1, result, count, NULL, NULL) ==
        0)
    {
        *error_code = error_as_int(GetLastError());
        free(result);
        return NULL;
    }
    return result;
}

char *os_environment_entry(int index, int *error_code)
{
    LPWCH environment;
    const wchar_t *entry;
    int current = 0;
    char *result = NULL;
    if (index < 0 || error_code == NULL)
        return NULL;
    *error_code = 0;
    environment = GetEnvironmentStringsW();
    if (environment == NULL)
    {
        *error_code = error_as_int(GetLastError());
        return NULL;
    }
    entry = environment;
    while (*entry != L'\0' && current < index)
    {
        entry += wcslen(entry) + 1;
        ++current;
    }
    if (*entry != L'\0')
        result = wide_to_utf8(entry, error_code);
    (void)FreeEnvironmentStringsW(environment);
    return result;
}

static int append_wide(wide_buffer *buffer, wchar_t value)
{
    size_t capacity;
    wchar_t *data;
    if (buffer->count + 2 > buffer->capacity)
    {
        capacity = buffer->capacity == 0 ? 64 : buffer->capacity * 2;
        data = (wchar_t *)realloc(buffer->data, capacity * sizeof(wchar_t));
        if (data == NULL)
            return 0;
        buffer->data = data;
        buffer->capacity = capacity;
    }
    buffer->data[buffer->count++] = value;
    buffer->data[buffer->count] = L'\0';
    return 1;
}

static int append_backslashes(wide_buffer *buffer, size_t count)
{
    while (count-- > 0)
    {
        if (!append_wide(buffer, L'\\'))
            return 0;
    }
    return 1;
}

static int append_argument(wide_buffer *buffer, const wchar_t *argument)
{
    const wchar_t *cursor;
    size_t backslashes;
    int quoted = argument[0] == L'\0' || wcspbrk(argument, L" \t\n\v\"") != NULL;
    if (!quoted)
    {
        for (cursor = argument; *cursor != L'\0'; ++cursor)
        {
            if (!append_wide(buffer, *cursor))
                return 0;
        }
        return 1;
    }
    if (!append_wide(buffer, L'\"'))
        return 0;
    cursor = argument;
    while (*cursor != L'\0')
    {
        backslashes = 0;
        while (*cursor == L'\\')
        {
            ++backslashes;
            ++cursor;
        }
        if (*cursor == L'\"')
        {
            if (!append_backslashes(buffer, backslashes * 2 + 1) || !append_wide(buffer, *cursor++))
                return 0;
        }
        else if (*cursor == L'\0')
        {
            if (!append_backslashes(buffer, backslashes * 2))
                return 0;
        }
        else
        {
            if (!append_backslashes(buffer, backslashes) || !append_wide(buffer, *cursor++))
                return 0;
        }
    }
    return append_wide(buffer, L'\"');
}

static wchar_t *build_command_line(char *const arguments[], int *error_code)
{
    wide_buffer buffer = {0};
    wchar_t *argument;
    size_t index;
    for (index = 0; arguments[index] != NULL; ++index)
    {
        argument = utf8_to_wide(arguments[index], error_code);
        if (argument == NULL)
        {
            free(buffer.data);
            return NULL;
        }
        if ((index > 0 && !append_wide(&buffer, L' ')) || !append_argument(&buffer, argument))
        {
            free(argument);
            free(buffer.data);
            *error_code = ERROR_NOT_ENOUGH_MEMORY;
            return NULL;
        }
        free(argument);
    }
    if (buffer.data == NULL)
        *error_code = ERROR_INVALID_PARAMETER;
    return buffer.data;
}

static int compare_environment_entries(const void *left, const void *right)
{
    const wchar_t *const *left_entry = (const wchar_t *const *)left;
    const wchar_t *const *right_entry = (const wchar_t *const *)right;
    return _wcsicmp(*left_entry, *right_entry);
}

static wchar_t *build_environment_block(char *const environment[], int *error_code)
{
    wchar_t **entries = NULL;
    wchar_t *block = NULL;
    size_t count = 0;
    size_t index;
    size_t block_count = 1;
    size_t offset = 0;

    while (environment[count] != NULL)
        ++count;
    if (count > 0)
    {
        entries = (wchar_t **)calloc(count, sizeof(*entries));
        if (entries == NULL)
        {
            *error_code = ERROR_NOT_ENOUGH_MEMORY;
            return NULL;
        }
    }
    for (index = 0; index < count; ++index)
    {
        entries[index] = utf8_to_wide(environment[index], error_code);
        if (entries[index] == NULL)
            goto fail;
        block_count += wcslen(entries[index]) + 1;
    }
    if (count > 1)
        qsort(entries, count, sizeof(*entries), compare_environment_entries);
    if (block_count < 2)
        block_count = 2;
    block = (wchar_t *)calloc(block_count, sizeof(*block));
    if (block == NULL)
    {
        *error_code = ERROR_NOT_ENOUGH_MEMORY;
        goto fail;
    }
    for (index = 0; index < count; ++index)
    {
        size_t entry_count = wcslen(entries[index]) + 1;
        wmemcpy(block + offset, entries[index], entry_count);
        offset += entry_count;
    }

fail:
    for (index = 0; index < count; ++index)
        free(entries[index]);
    free(entries);
    return block;
}

static void close_handle(HANDLE *handle)
{
    if (*handle != NULL && *handle != INVALID_HANDLE_VALUE)
    {
        (void)CloseHandle(*handle);
        *handle = NULL;
    }
}

static int duplicate_inheritable(HANDLE source, HANDLE *result)
{
    if (source == NULL || source == INVALID_HANDLE_VALUE)
        return ERROR_INVALID_HANDLE;
    if (!DuplicateHandle(GetCurrentProcess(), source, GetCurrentProcess(), result, 0, TRUE,
                         DUPLICATE_SAME_ACCESS))
        return error_as_int(GetLastError());
    return 0;
}

static int append_unique_handle(HANDLE handles[], SIZE_T *count, HANDLE handle)
{
    SIZE_T index;
    for (index = 0; index < *count; ++index)
    {
        if (handles[index] == handle)
            return 1;
    }
    handles[(*count)++] = handle;
    return 1;
}

os_process *os_process_start(const char *executable, char *const arguments[],
                             char *const environment[], const char *working_directory,
                             int stdin_mode, int stdout_mode, int stderr_mode,
                             int allow_terminal_stdin,
                             int *error_code)
{
    SECURITY_ATTRIBUTES security = {sizeof(security), NULL, TRUE};
    HANDLE stdout_read = NULL, stdout_write = NULL;
    HANDLE stderr_read = NULL, stderr_write = NULL;
    HANDLE stdin_read = NULL, stdin_write = NULL;
    HANDLE child_stdin = NULL, child_stdout = NULL, child_stderr = NULL;
    STARTUPINFOEXW startup = {0};
    PROCESS_INFORMATION information = {0};
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION job_limits = {0};
    SIZE_T attributes_size = 0;
    HANDLE inherited[3];
    HANDLE job = NULL;
    SIZE_T inherited_count = 0;
    wchar_t *command_line = NULL;
    wchar_t *application_name = NULL;
    wchar_t *environment_block = NULL;
    wchar_t *working_directory_wide = NULL;
    os_process *process = NULL;
    DWORD windows_error = ERROR_SUCCESS;
    ULONGLONG started_at = 0;

    if (error_code == NULL)
        return NULL;
    *error_code = 0;
    if (executable == NULL || arguments == NULL || environment == NULL ||
        (stdin_mode != OS_PROCESS_STDIN_PIPE && stdin_mode != OS_PROCESS_STDIN_INHERIT) ||
        (stdout_mode != OS_PROCESS_OUTPUT_CAPTURE &&
         stdout_mode != OS_PROCESS_OUTPUT_INHERIT && stdout_mode != OS_PROCESS_OUTPUT_DISCARD) ||
        (stderr_mode != OS_PROCESS_OUTPUT_CAPTURE &&
         stderr_mode != OS_PROCESS_OUTPUT_INHERIT &&
         stderr_mode != OS_PROCESS_OUTPUT_DISCARD && stderr_mode != OS_PROCESS_STDERR_MERGE) ||
        (allow_terminal_stdin != 0 && allow_terminal_stdin != 1))
    {
        *error_code = ERROR_INVALID_PARAMETER;
        return NULL;
    }
    command_line = build_command_line(arguments, error_code);
    if (command_line == NULL)
        goto fail;
    application_name = utf8_to_wide(executable, error_code);
    if (application_name == NULL)
        goto fail;
    environment_block = build_environment_block(environment, error_code);
    if (environment_block == NULL)
        goto fail;
    if (working_directory != NULL)
    {
        working_directory_wide = utf8_to_wide(working_directory, error_code);
        if (working_directory_wide == NULL)
            goto fail;
    }
    job = CreateJobObjectW(NULL, NULL);
    if (job == NULL)
    {
        windows_error = GetLastError();
        goto fail;
    }
    /* Closing the last library-owned Job Object handle is a containment safety
       net. Normal termination also targets the job explicitly. */
    job_limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &job_limits,
                                 sizeof(job_limits)))
    {
        windows_error = GetLastError();
        goto fail;
    }
    if (stdin_mode == OS_PROCESS_STDIN_PIPE)
    {
        if (!CreatePipe(&stdin_read, &stdin_write, &security, 0) ||
            !SetHandleInformation(stdin_write, HANDLE_FLAG_INHERIT, 0))
        {
            windows_error = GetLastError();
            goto fail;
        }
        child_stdin = stdin_read;
    }
    else
    {
        windows_error = (DWORD)duplicate_inheritable(GetStdHandle(STD_INPUT_HANDLE), &child_stdin);
        if (windows_error != ERROR_SUCCESS)
            goto fail;
    }
    if (stdout_mode == OS_PROCESS_OUTPUT_CAPTURE)
    {
        if (!CreatePipe(&stdout_read, &stdout_write, &security, 0) ||
            !SetHandleInformation(stdout_read, HANDLE_FLAG_INHERIT, 0))
        {
            windows_error = GetLastError();
            goto fail;
        }
        child_stdout = stdout_write;
    }
    else if (stdout_mode == OS_PROCESS_OUTPUT_INHERIT)
    {
        windows_error = (DWORD)duplicate_inheritable(GetStdHandle(STD_OUTPUT_HANDLE), &child_stdout);
        if (windows_error != ERROR_SUCCESS)
            goto fail;
    }
    else
    {
        child_stdout = CreateFileW(L"NUL", GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                   &security, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
        if (child_stdout == INVALID_HANDLE_VALUE)
        {
            child_stdout = NULL;
            windows_error = GetLastError();
            goto fail;
        }
    }
    if (stderr_mode == OS_PROCESS_OUTPUT_CAPTURE)
    {
        if (!CreatePipe(&stderr_read, &stderr_write, &security, 0) ||
            !SetHandleInformation(stderr_read, HANDLE_FLAG_INHERIT, 0))
        {
            windows_error = GetLastError();
            goto fail;
        }
        child_stderr = stderr_write;
    }
    else if (stderr_mode == OS_PROCESS_OUTPUT_INHERIT)
    {
        windows_error = (DWORD)duplicate_inheritable(GetStdHandle(STD_ERROR_HANDLE), &child_stderr);
        if (windows_error != ERROR_SUCCESS)
            goto fail;
    }
    else if (stderr_mode == OS_PROCESS_OUTPUT_DISCARD)
    {
        child_stderr = CreateFileW(L"NUL", GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                   &security, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
        if (child_stderr == INVALID_HANDLE_VALUE)
        {
            child_stderr = NULL;
            windows_error = GetLastError();
            goto fail;
        }
    }
    else
    {
        child_stderr = child_stdout;
    }
    ZeroMemory(&startup, sizeof(startup));
    startup.StartupInfo.cb = sizeof(startup);
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startup.StartupInfo.hStdInput = child_stdin;
    startup.StartupInfo.hStdOutput = child_stdout;
    startup.StartupInfo.hStdError = child_stderr;
    append_unique_handle(inherited, &inherited_count, child_stdin);
    append_unique_handle(inherited, &inherited_count, child_stdout);
    append_unique_handle(inherited, &inherited_count, child_stderr);
    (void)InitializeProcThreadAttributeList(NULL, 1, 0, &attributes_size);
    startup.lpAttributeList = (PPROC_THREAD_ATTRIBUTE_LIST)malloc(attributes_size);
    if (startup.lpAttributeList == NULL)
    {
        windows_error = ERROR_NOT_ENOUGH_MEMORY;
        goto fail;
    }
    if (!InitializeProcThreadAttributeList(startup.lpAttributeList, 1, 0, &attributes_size) ||
        !UpdateProcThreadAttribute(startup.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                                   inherited, inherited_count * sizeof(HANDLE), NULL, NULL))
    {
        windows_error = GetLastError();
        goto fail;
    }

    ZeroMemory(&information, sizeof(information));
    /* CreateProcessW does not resolve an executable with the PATH contained in
       lpEnvironment. OS_COMMAND has already resolved application_name so the
       child environment and executable lookup use the same snapshot. */
    started_at = GetTickCount64();
    if (!CreateProcessW(application_name, command_line, NULL, NULL, TRUE,
                        EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT |
                            CREATE_SUSPENDED,
                        environment_block, working_directory_wide,
                        &startup.StartupInfo, &information))
    {
        windows_error = GetLastError();
        goto fail;
    }
    /* Suspension closes the race in which the new process could create an
       uncontained descendant before assignment to the job. */
    if (!AssignProcessToJobObject(job, information.hProcess))
    {
        windows_error = GetLastError();
        (void)TerminateProcess(information.hProcess, 1);
        (void)WaitForSingleObject(information.hProcess, INFINITE);
        (void)CloseHandle(information.hThread);
        (void)CloseHandle(information.hProcess);
        information.hThread = NULL;
        information.hProcess = NULL;
        goto fail;
    }
    if (ResumeThread(information.hThread) == (DWORD)-1)
    {
        windows_error = GetLastError();
        (void)TerminateJobObject(job, 1);
        (void)WaitForSingleObject(information.hProcess, INFINITE);
        (void)CloseHandle(information.hThread);
        (void)CloseHandle(information.hProcess);
        information.hThread = NULL;
        information.hProcess = NULL;
        goto fail;
    }
    (void)CloseHandle(information.hThread);
    if (child_stderr == child_stdout)
        child_stderr = NULL;
    else
        close_handle(&child_stderr);
    close_handle(&child_stdout);
    close_handle(&child_stdin);
    stdout_write = NULL;
    stderr_write = NULL;
    stdin_read = NULL;
    process = (os_process *)calloc(1, sizeof(*process));
    if (process == NULL)
    {
        (void)TerminateJobObject(job, 1);
        (void)WaitForSingleObject(information.hProcess, INFINITE);
        (void)CloseHandle(information.hProcess);
        windows_error = ERROR_NOT_ENOUGH_MEMORY;
        goto fail;
    }
    process->process = information.hProcess;
    process->job = job;
    process->stdin_write = stdin_write;
    process->stdout_read = stdout_read;
    process->stderr_read = stderr_read;
    process->started_at = started_at;
    process->exit_code = -1;
    stdin_write = NULL;
    stdout_read = NULL;
    stderr_read = NULL;
    job = NULL;

fail:
    if (startup.lpAttributeList != NULL)
    {
        DeleteProcThreadAttributeList(startup.lpAttributeList);
        free(startup.lpAttributeList);
    }
    free(command_line);
    free(application_name);
    free(environment_block);
    free(working_directory_wide);
    close_handle(&stdout_read);
    close_handle(&stderr_read);
    close_handle(&stdin_write);
    if (child_stderr == child_stdout)
        child_stderr = NULL;
    else
        close_handle(&child_stderr);
    close_handle(&child_stdout);
    close_handle(&child_stdin);
    close_handle(&job);
    if (process == NULL && windows_error != ERROR_SUCCESS)
    {
        *error_code = error_as_int(windows_error);
    }
    return process;
}

static int read_handle(HANDLE handle, void *buffer, int capacity)
{
    DWORD count = 0;
    DWORD error;
    if (buffer == NULL || capacity <= 0)
        return -ERROR_INVALID_PARAMETER;
    if (!ReadFile(handle, buffer, (DWORD)capacity, &count, NULL))
    {
        error = GetLastError();
        return error == ERROR_BROKEN_PIPE ? 0 : -error_as_int(error);
    }
    return (int)count;
}

int os_process_read_stdout(os_process *process, void *buffer, int capacity)
{
    return process == NULL ? -ERROR_INVALID_PARAMETER
                           : read_handle(process->stdout_read, buffer, capacity);
}

int os_process_read_stderr(os_process *process, void *buffer, int capacity)
{
    return process == NULL ? -ERROR_INVALID_PARAMETER
                           : read_handle(process->stderr_read, buffer, capacity);
}

int os_process_write_stdin(os_process *process, const void *buffer, int capacity)
{
    DWORD count = 0;
    DWORD error;
    if (process == NULL || buffer == NULL || capacity <= 0)
    {
        return -ERROR_INVALID_PARAMETER;
    }
    if (process->stdin_write == NULL)
        return 0;
    if (!WriteFile(process->stdin_write, buffer, (DWORD)capacity, &count, NULL))
    {
        error = GetLastError();
        return error == ERROR_BROKEN_PIPE || error == ERROR_NO_DATA ? 0 : -error_as_int(error);
    }
    return (int)count;
}

int os_process_close_stdin(os_process *process)
{
    HANDLE handle;
    if (process == NULL)
        return ERROR_INVALID_PARAMETER;
    if (process->stdin_write == NULL)
        return 0;
    handle = process->stdin_write;
    process->stdin_write = NULL;
    return CloseHandle(handle) ? 0 : error_as_int(GetLastError());
}

void os_process_cancel_io(os_process *process)
{
    if (process != NULL)
    {
        /* The Job Object is terminated before cancellation, so descendants no
           longer own pipe counterparts. Closing here is the final cutoff for a
           platform pipe operation that nevertheless did not observe EOF. */
        close_handle(&process->stdin_write);
        close_handle(&process->stdout_read);
        close_handle(&process->stderr_read);
    }
}

static int store_exit_code(os_process *process, int *exit_code)
{
    DWORD native_code;
    if (!GetExitCodeProcess(process->process, &native_code))
        return error_as_int(GetLastError());
    process->exit_code = (int)native_code;
    process->has_exited = 1;
    *exit_code = process->exit_code;
    return 0;
}

int os_process_wait(os_process *process, int *exit_code)
{
    if (process == NULL || exit_code == NULL)
        return ERROR_INVALID_PARAMETER;
    if (process->has_exited)
    {
        *exit_code = process->exit_code;
        return 0;
    }
    if (WaitForSingleObject(process->process, INFINITE) != WAIT_OBJECT_0)
    {
        return error_as_int(GetLastError());
    }
    return store_exit_code(process, exit_code);
}

int os_process_timeout_remaining(os_process *process, int timeout_milliseconds)
{
    ULONGLONG elapsed;
    if (process == NULL || timeout_milliseconds <= 0)
        return 0;
    elapsed = GetTickCount64() - process->started_at;
    return elapsed >= (ULONGLONG)timeout_milliseconds
               ? 0
               : timeout_milliseconds - (int)elapsed;
}

int os_process_wait_for(os_process *process, int timeout_milliseconds,
                        int *timed_out, int *exit_code)
{
    DWORD result;
    int remaining;
    if (process == NULL || timeout_milliseconds <= 0 || timed_out == NULL || exit_code == NULL)
        return ERROR_INVALID_PARAMETER;
    remaining = os_process_timeout_remaining(process, timeout_milliseconds);
    if (remaining == 0)
    {
        *timed_out = 1;
        *exit_code = -1;
        return 0;
    }
    result = WaitForSingleObject(process->process, (DWORD)remaining);
    if (result == WAIT_TIMEOUT)
    {
        *timed_out = 1;
        *exit_code = -1;
        return 0;
    }
    if (result != WAIT_OBJECT_0)
        return error_as_int(GetLastError());
    *timed_out = 0;
    return store_exit_code(process, exit_code);
}

int os_process_restore_terminal(os_process *process)
{
    return process == NULL ? ERROR_INVALID_PARAMETER : 0;
}

int os_process_terminate(os_process *process)
{
    if (process == NULL)
        return ERROR_INVALID_PARAMETER;
    return TerminateJobObject(process->job, 1) ? 0 : error_as_int(GetLastError());
}

int os_process_force_terminate(os_process *process)
{
    if (process == NULL)
        return ERROR_INVALID_PARAMETER;
    return TerminateJobObject(process->job, 1) ? 0 : error_as_int(GetLastError());
}

void os_process_free(os_process *process)
{
    if (process != NULL)
    {
        close_handle(&process->stdin_write);
        close_handle(&process->stdout_read);
        close_handle(&process->stderr_read);
        close_handle(&process->process);
        close_handle(&process->job);
        free(process);
    }
}

#endif
