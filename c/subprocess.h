#ifndef OS_PROCESS_SUBPROCESS_H
#define OS_PROCESS_SUBPROCESS_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct os_process os_process;

/*
 * Start a process from a NULL-terminated UTF-8 argument vector whose first
 * item names the executable. working_directory may be NULL. On success the
 * caller owns the returned process and error_code is zero. On failure NULL is
 * returned and error_code receives a positive platform error code.
 */
os_process *os_process_start(
    const char *executable,
    char *const arguments[],
    const char *working_directory,
    int *error_code
);

/*
 * Exactly one caller may use each standard-I/O endpoint. The stdout reader,
 * stderr reader, and stdin writer may run concurrently with one another and
 * with poll or wait. A read or write returns a positive byte count, zero for
 * EOF or a normally closed pipe, and a negative platform error code. Closing
 * stdin is idempotent and returns zero or a positive platform error code; it
 * must be serialized with writes by the caller.
 */
int os_process_read_stdout(os_process *process, void *buffer, int capacity);
int os_process_read_stderr(os_process *process, void *buffer, int capacity);
int os_process_write_stdin(os_process *process, const void *buffer, int capacity);
int os_process_close_stdin(os_process *process);

/*
 * Lifecycle calls return zero on success or a positive platform error code.
 * Poll and wait retain the exit code, so either may be repeated after reaping
 * the child. Lifecycle calls must be serialized with one another. Terminate
 * only requests platform-dependent termination; the caller must still poll or
 * wait. Exit-code interpretation is platform-specific.
 */
int os_process_poll(os_process *process, int *finished, int *exit_code);
int os_process_wait(os_process *process, int *exit_code);
int os_process_terminate(os_process *process);

/*
 * Force child termination during recovery from a partially initialized or
 * otherwise unsafe lifecycle. This is not the public termination operation;
 * the caller must still wait for the child and finish active pipe operations.
 */
int os_process_force_terminate(os_process *process);

/*
 * Release the process and its pipe endpoints. This does not terminate or reap
 * a child. The child must already be reaped and no pipe operation may remain
 * active. Passing NULL is allowed.
 */
void os_process_free(os_process *process);

#ifdef __cplusplus
}
#endif

#endif
