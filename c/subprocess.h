#ifndef OS_PROCESS_SUBPROCESS_H
#define OS_PROCESS_SUBPROCESS_H

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct os_process os_process;

    enum
    {
        OS_PROCESS_STDIN_PIPE = 0,
        OS_PROCESS_STDIN_INHERIT = 1
    };

    enum
    {
        OS_PROCESS_OUTPUT_CAPTURE = 0,
        OS_PROCESS_OUTPUT_INHERIT = 1,
        OS_PROCESS_OUTPUT_DISCARD = 2,
        OS_PROCESS_STDERR_MERGE = 3
    };

    /*
     * Return an allocated UTF-8 copy of environment entry index, or NULL when
     * index is past the end. The caller owns a non-NULL result and releases it
     * with free. error_code is zero for success/end and positive on failure.
     */
    char *os_environment_entry(int index, int *error_code);

    /*
     * Start a process from NULL-terminated UTF-8 argument and environment
     * vectors. executable is already resolved and the environment entries have
     * NAME=VALUE form. working_directory may be NULL. On POSIX the environment
     * vector is passed directly to posix_spawn. On Windows it is converted to a
     * sorted UTF-16 environment block for CreateProcessW. On success the caller
     * owns the returned process and error_code is zero. On failure NULL is
     * returned and error_code receives a positive platform error code.
     */
    os_process *os_process_start(const char *executable, char *const arguments[],
                                 char *const environment[], const char *working_directory,
                                 int stdin_mode, int stdout_mode, int stderr_mode,
                                 int *error_code);

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
     * forcefully kills the managed process group or Job Object; the caller must
     * still poll or wait. Exit-code interpretation is platform-specific.
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
