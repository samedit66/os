#ifndef OS_PROCESS_SUBPROCESS_H
#define OS_PROCESS_SUBPROCESS_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct os_process os_process;

os_process *os_process_start(
    const char *executable,
    char *const arguments[],
    const char *working_directory,
    int *error_code
);
int os_process_read_stdout(os_process *process, void *buffer, int capacity);
int os_process_read_stderr(os_process *process, void *buffer, int capacity);
int os_process_write_stdin(os_process *process, const void *buffer, int capacity);
int os_process_close_stdin(os_process *process);
int os_process_poll(os_process *process, int *finished, int *exit_code);
int os_process_wait(os_process *process, int *exit_code);
int os_process_terminate(os_process *process);
void os_process_free(os_process *process);
int os_process_is_command_error(int error_code);

#ifdef __cplusplus
}
#endif

#endif
