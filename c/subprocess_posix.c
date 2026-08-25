#ifndef _WIN32

#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

#include "subprocess.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

struct os_process {
    pid_t pid;
    int stdout_fd;
    int stderr_fd;
    int exit_code;
    int has_exited;
};

static void close_fd(int *fd)
{
    if (*fd >= 0) {
        (void)close(*fd);
        *fd = -1;
    }
}

static int set_close_on_exec(int fd)
{
    int flags = fcntl(fd, F_GETFD);
    if (flags < 0 || fcntl(fd, F_SETFD, flags | FD_CLOEXEC) < 0) {
        return errno;
    }
    return 0;
}

static int decoded_exit_code(int status)
{
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        return -WTERMSIG(status);
    }
    return -1;
}

os_process *os_process_start(
    const char *executable,
    char *const arguments[],
    int *error_code
)
{
    int stdout_pipe[2] = {-1, -1};
    int stderr_pipe[2] = {-1, -1};
    posix_spawn_file_actions_t actions;
    int actions_initialized = 0;
    int result = EINVAL;
    pid_t pid;
    os_process *process = NULL;

    if (error_code != NULL) {
        *error_code = 0;
    }
    if (executable == NULL || arguments == NULL || error_code == NULL) {
        return NULL;
    }
    if (pipe(stdout_pipe) != 0) {
        result = errno;
        goto fail;
    }
    if (pipe(stderr_pipe) != 0) {
        result = errno;
        goto fail;
    }
    result = set_close_on_exec(stdout_pipe[0]);
    if (result != 0) goto fail;
    result = set_close_on_exec(stdout_pipe[1]);
    if (result != 0) goto fail;
    result = set_close_on_exec(stderr_pipe[0]);
    if (result != 0) goto fail;
    result = set_close_on_exec(stderr_pipe[1]);
    if (result != 0) goto fail;

    result = posix_spawn_file_actions_init(&actions);
    if (result != 0) goto fail;
    actions_initialized = 1;
#define ADD_ACTION(call) do { result = (call); if (result != 0) goto fail; } while (0)
    ADD_ACTION(posix_spawn_file_actions_adddup2(&actions, stdout_pipe[1], STDOUT_FILENO));
    ADD_ACTION(posix_spawn_file_actions_adddup2(&actions, stderr_pipe[1], STDERR_FILENO));
    ADD_ACTION(posix_spawn_file_actions_addclose(&actions, stdout_pipe[0]));
    ADD_ACTION(posix_spawn_file_actions_addclose(&actions, stderr_pipe[0]));
    ADD_ACTION(posix_spawn_file_actions_addclose(&actions, stdout_pipe[1]));
    ADD_ACTION(posix_spawn_file_actions_addclose(&actions, stderr_pipe[1]));
#undef ADD_ACTION

    result = posix_spawnp(&pid, executable, &actions, NULL, arguments, environ);
    if (result != 0) goto fail;
    (void)posix_spawn_file_actions_destroy(&actions);
    actions_initialized = 0;
    close_fd(&stdout_pipe[1]);
    close_fd(&stderr_pipe[1]);

    process = (os_process *)calloc(1, sizeof(*process));
    if (process == NULL) {
        result = ENOMEM;
        (void)kill(pid, SIGTERM);
        while (waitpid(pid, NULL, 0) < 0 && errno == EINTR) {
        }
        goto fail;
    }
    process->pid = pid;
    process->stdout_fd = stdout_pipe[0];
    process->stderr_fd = stderr_pipe[0];
    process->exit_code = -1;
    stdout_pipe[0] = -1;
    stderr_pipe[0] = -1;
    return process;

fail:
    if (actions_initialized) {
        (void)posix_spawn_file_actions_destroy(&actions);
    }
    close_fd(&stdout_pipe[0]);
    close_fd(&stdout_pipe[1]);
    close_fd(&stderr_pipe[0]);
    close_fd(&stderr_pipe[1]);
    *error_code = result;
    return NULL;
}

static int read_fd(int fd, void *buffer, int capacity)
{
    ssize_t count;
    if (buffer == NULL || capacity <= 0) return -EINVAL;
    do {
        count = read(fd, buffer, (size_t)capacity);
    } while (count < 0 && errno == EINTR);
    return count < 0 ? -errno : (int)count;
}

int os_process_read_stdout(os_process *process, void *buffer, int capacity)
{
    return process == NULL ? -EINVAL : read_fd(process->stdout_fd, buffer, capacity);
}

int os_process_read_stderr(os_process *process, void *buffer, int capacity)
{
    return process == NULL ? -EINVAL : read_fd(process->stderr_fd, buffer, capacity);
}

int os_process_poll(os_process *process, int *finished, int *exit_code)
{
    int status;
    pid_t result;
    if (process == NULL || finished == NULL || exit_code == NULL) return EINVAL;
    if (process->has_exited) {
        *finished = 1;
        *exit_code = process->exit_code;
        return 0;
    }
    do {
        result = waitpid(process->pid, &status, WNOHANG);
    } while (result < 0 && errno == EINTR);
    if (result < 0) return errno;
    if (result == 0) {
        *finished = 0;
        *exit_code = -1;
        return 0;
    }
    process->exit_code = decoded_exit_code(status);
    process->has_exited = 1;
    *finished = 1;
    *exit_code = process->exit_code;
    return 0;
}

int os_process_wait(os_process *process, int *exit_code)
{
    int status;
    pid_t result;
    if (process == NULL || exit_code == NULL) return EINVAL;
    if (process->has_exited) {
        *exit_code = process->exit_code;
        return 0;
    }
    do {
        result = waitpid(process->pid, &status, 0);
    } while (result < 0 && errno == EINTR);
    if (result < 0) return errno;
    process->exit_code = decoded_exit_code(status);
    process->has_exited = 1;
    *exit_code = process->exit_code;
    return 0;
}

int os_process_terminate(os_process *process)
{
    if (process == NULL) return EINVAL;
    if (process->has_exited) return 0;
    return kill(process->pid, SIGTERM) == 0 ? 0 : errno;
}

void os_process_free(os_process *process)
{
    if (process != NULL) {
        close_fd(&process->stdout_fd);
        close_fd(&process->stderr_fd);
        free(process);
    }
}

int os_process_is_command_error(int error_code)
{
    return error_code == ENOENT || error_code == EACCES || error_code == ENOEXEC;
}

#endif
