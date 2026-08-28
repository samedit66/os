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

#include "subprocess.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

struct os_process
{
    pid_t pid;
    int stdin_fd;
    int stdout_fd;
    int stderr_fd;
    int cancel_read_fd;
    int cancel_write_fd;
    atomic_int io_cancelled;
    struct timespec started_at;
    pid_t parent_foreground_group;
    int terminal_handed_off;
    int exit_code;
    int has_exited;
};

char *os_environment_entry(int index, int *error_code)
{
    char *result;
    size_t count;
    if (index < 0 || error_code == NULL)
        return NULL;
    *error_code = 0;
    if (environ == NULL || environ[index] == NULL)
        return NULL;
    count = strlen(environ[index]) + 1;
    result = (char *)malloc(count);
    if (result == NULL)
    {
        *error_code = ENOMEM;
        return NULL;
    }
    memcpy(result, environ[index], count);
    return result;
}

static void close_fd(int *fd)
{
    if (*fd >= 0)
    {
        (void)close(*fd);
        *fd = -1;
    }
}

static int set_close_on_exec(int fd)
{
    int flags = fcntl(fd, F_GETFD);
    if (flags < 0 || fcntl(fd, F_SETFD, flags | FD_CLOEXEC) < 0)
    {
        return errno;
    }
    return 0;
}

static int set_nonblocking(int fd)
{
    int flags = fcntl(fd, F_GETFL);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0)
        return errno;
    return 0;
}

static int set_terminal_foreground_group(int terminal_fd, pid_t process_group)
{
    sigset_t blocked;
    sigset_t old_mask;
    int result;
    int mask_error;
    if (sigemptyset(&blocked) != 0 || sigaddset(&blocked, SIGTTOU) != 0)
        return errno;
    mask_error = pthread_sigmask(SIG_BLOCK, &blocked, &old_mask);
    if (mask_error != 0)
        return mask_error;
    result = tcsetpgrp(terminal_fd, process_group) == 0 ? 0 : errno;
    mask_error = pthread_sigmask(SIG_SETMASK, &old_mask, NULL);
    return result != 0 ? result : mask_error;
}

#if defined(__APPLE__) && defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
static int add_working_directory_action(posix_spawn_file_actions_t *actions,
                                        const char *working_directory)
{
    return posix_spawn_file_actions_addchdir_np(actions, working_directory);
}
#if defined(__APPLE__) && defined(__clang__)
#pragma clang diagnostic pop
#endif

static int decoded_exit_code(int status)
{
    if (WIFEXITED(status))
    {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status))
    {
        return -WTERMSIG(status);
    }
    return -1;
}

os_process *os_process_start(const char *executable, char *const arguments[],
                             char *const environment[], const char *working_directory,
                             int stdin_mode, int stdout_mode, int stderr_mode,
                             int allow_terminal_stdin,
                             int *error_code)
{
    int stdin_pipe[2] = {-1, -1};
    int stdout_pipe[2] = {-1, -1};
    int stderr_pipe[2] = {-1, -1};
    int cancel_pipe[2] = {-1, -1};
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    int actions_initialized = 0;
    int attributes_initialized = 0;
    int result = EINVAL;
    pid_t pid;
    os_process *process = NULL;
    struct timespec started_at;
    pid_t parent_foreground_group = -1;
    int terminal_handed_off = 0;

    if (error_code != NULL)
    {
        *error_code = 0;
    }
    if (executable == NULL || arguments == NULL || environment == NULL || error_code == NULL ||
        (stdin_mode != OS_PROCESS_STDIN_PIPE && stdin_mode != OS_PROCESS_STDIN_INHERIT) ||
        (stdout_mode != OS_PROCESS_OUTPUT_CAPTURE &&
         stdout_mode != OS_PROCESS_OUTPUT_INHERIT && stdout_mode != OS_PROCESS_OUTPUT_DISCARD) ||
        (stderr_mode != OS_PROCESS_OUTPUT_CAPTURE &&
         stderr_mode != OS_PROCESS_OUTPUT_INHERIT &&
         stderr_mode != OS_PROCESS_OUTPUT_DISCARD && stderr_mode != OS_PROCESS_STDERR_MERGE) ||
        (allow_terminal_stdin != 0 && allow_terminal_stdin != 1))
    {
        return NULL;
    }
    if (stdin_mode == OS_PROCESS_STDIN_INHERIT && isatty(STDIN_FILENO) &&
        !allow_terminal_stdin)
    {
        *error_code = ENOTSUP;
        return NULL;
    }
    if (stdin_mode == OS_PROCESS_STDIN_INHERIT && isatty(STDIN_FILENO))
    {
        parent_foreground_group = tcgetpgrp(STDIN_FILENO);
        if (parent_foreground_group < 0)
        {
            *error_code = errno;
            return NULL;
        }
    }
    if (stdin_mode == OS_PROCESS_STDIN_PIPE && pipe(stdin_pipe) != 0)
    {
        result = errno;
        goto fail;
    }
    if (stdout_mode == OS_PROCESS_OUTPUT_CAPTURE && pipe(stdout_pipe) != 0)
    {
        result = errno;
        goto fail;
    }
    if (stderr_mode == OS_PROCESS_OUTPUT_CAPTURE && pipe(stderr_pipe) != 0)
    {
        result = errno;
        goto fail;
    }
    if (pipe(cancel_pipe) != 0)
    {
        result = errno;
        goto fail;
    }
    result = set_close_on_exec(cancel_pipe[0]);
    if (result != 0)
        goto fail;
    result = set_close_on_exec(cancel_pipe[1]);
    if (result != 0)
        goto fail;
    if (stdin_mode == OS_PROCESS_STDIN_PIPE)
    {
        result = set_close_on_exec(stdin_pipe[0]);
        if (result != 0)
            goto fail;
        result = set_close_on_exec(stdin_pipe[1]);
        if (result != 0)
            goto fail;
    }
    if (stdout_mode == OS_PROCESS_OUTPUT_CAPTURE)
    {
        result = set_close_on_exec(stdout_pipe[0]);
        if (result != 0)
            goto fail;
        result = set_close_on_exec(stdout_pipe[1]);
        if (result != 0)
            goto fail;
    }
    if (stderr_mode == OS_PROCESS_OUTPUT_CAPTURE)
    {
        result = set_close_on_exec(stderr_pipe[0]);
        if (result != 0)
            goto fail;
        result = set_close_on_exec(stderr_pipe[1]);
        if (result != 0)
            goto fail;
    }

    result = posix_spawn_file_actions_init(&actions);
    if (result != 0)
        goto fail;
    actions_initialized = 1;
    result = posix_spawnattr_init(&attributes);
    if (result != 0)
        goto fail;
    attributes_initialized = 1;
    result = posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETPGROUP);
    if (result != 0)
        goto fail;
    result = posix_spawnattr_setpgroup(&attributes, 0);
    if (result != 0)
        goto fail;
#define ADD_ACTION(call)                                                                           \
    do                                                                                             \
    {                                                                                              \
        result = (call);                                                                           \
        if (result != 0)                                                                           \
            goto fail;                                                                             \
    } while (0)
    if (stdin_mode == OS_PROCESS_STDIN_PIPE)
    {
        ADD_ACTION(posix_spawn_file_actions_adddup2(&actions, stdin_pipe[0], STDIN_FILENO));
        ADD_ACTION(posix_spawn_file_actions_addclose(&actions, stdin_pipe[1]));
        ADD_ACTION(posix_spawn_file_actions_addclose(&actions, stdin_pipe[0]));
    }
    if (stdout_mode == OS_PROCESS_OUTPUT_CAPTURE)
    {
        ADD_ACTION(posix_spawn_file_actions_adddup2(&actions, stdout_pipe[1], STDOUT_FILENO));
        ADD_ACTION(posix_spawn_file_actions_addclose(&actions, stdout_pipe[0]));
        ADD_ACTION(posix_spawn_file_actions_addclose(&actions, stdout_pipe[1]));
    }
    else if (stdout_mode == OS_PROCESS_OUTPUT_DISCARD)
    {
        ADD_ACTION(posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null",
                                                    O_WRONLY, 0));
    }
    if (stderr_mode == OS_PROCESS_OUTPUT_CAPTURE)
    {
        ADD_ACTION(posix_spawn_file_actions_adddup2(&actions, stderr_pipe[1], STDERR_FILENO));
        ADD_ACTION(posix_spawn_file_actions_addclose(&actions, stderr_pipe[0]));
        ADD_ACTION(posix_spawn_file_actions_addclose(&actions, stderr_pipe[1]));
    }
    else if (stderr_mode == OS_PROCESS_OUTPUT_DISCARD)
    {
        ADD_ACTION(posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null",
                                                    O_WRONLY, 0));
    }
    else if (stderr_mode == OS_PROCESS_STDERR_MERGE)
    {
        /* Merge after configuring stdout so stderr follows the selected stdout
           destination, including a capture pipe. */
        ADD_ACTION(posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO));
    }
    if (working_directory != NULL)
    {
        ADD_ACTION(add_working_directory_action(&actions, working_directory));
    }
#undef ADD_ACTION

    /* OS_COMMAND resolves executable against its own PATH. Use posix_spawn,
       not posix_spawnp, so Unix cannot search the parent process environment. */
    /* Every launch starts a new process group. Public termination targets this
       group so descendants inheriting the group are killed together. A child
       that deliberately escapes with setsid/setpgid is outside this guarantee. */
    if (clock_gettime(CLOCK_MONOTONIC, &started_at) != 0)
    {
        result = errno;
        goto fail;
    }
    result = posix_spawn(&pid, executable, &actions, &attributes, arguments, environment);
    if (result != 0)
        goto fail;
    if (parent_foreground_group >= 0)
    {
        result = set_terminal_foreground_group(STDIN_FILENO, pid);
        if (result != 0)
        {
            (void)kill(-pid, SIGKILL);
            while (waitpid(pid, NULL, 0) < 0 && errno == EINTR)
            {
            }
            goto fail;
        }
        terminal_handed_off = 1;
        /* The child can attempt a terminal read in the short interval between
           spawn and tcsetpgrp and be stopped by SIGTTIN. Once foreground, make
           it runnable without treating an already-exited child as a failure. */
        (void)kill(-pid, SIGCONT);
    }
    (void)posix_spawn_file_actions_destroy(&actions);
    actions_initialized = 0;
    (void)posix_spawnattr_destroy(&attributes);
    attributes_initialized = 0;
    close_fd(&stdin_pipe[0]);
    close_fd(&stdout_pipe[1]);
    close_fd(&stderr_pipe[1]);

    process = (os_process *)calloc(1, sizeof(*process));
    if (process == NULL)
    {
        result = ENOMEM;
        (void)kill(-pid, SIGKILL);
        while (waitpid(pid, NULL, 0) < 0 && errno == EINTR)
        {
        }
        if (terminal_handed_off)
            (void)set_terminal_foreground_group(STDIN_FILENO, parent_foreground_group);
        goto fail;
    }
    process->pid = pid;
    process->stdin_fd = -1;
    process->stdout_fd = -1;
    process->stderr_fd = -1;
    process->cancel_read_fd = -1;
    process->cancel_write_fd = -1;
    process->stdin_fd = stdin_pipe[1];
    process->stdout_fd = stdout_pipe[0];
    process->stderr_fd = stderr_pipe[0];
    process->cancel_read_fd = cancel_pipe[0];
    process->cancel_write_fd = cancel_pipe[1];
    atomic_init(&process->io_cancelled, 0);
    process->started_at = started_at;
    process->parent_foreground_group = parent_foreground_group;
    process->terminal_handed_off = terminal_handed_off;
    process->exit_code = -1;
    stdin_pipe[1] = -1;
    stdout_pipe[0] = -1;
    stderr_pipe[0] = -1;
    cancel_pipe[0] = -1;
    cancel_pipe[1] = -1;
    if (process->stdin_fd >= 0)
        result = set_nonblocking(process->stdin_fd);
    if (result == 0 && process->stdout_fd >= 0)
        result = set_nonblocking(process->stdout_fd);
    if (result == 0 && process->stderr_fd >= 0)
        result = set_nonblocking(process->stderr_fd);
    if (result != 0)
    {
        (void)kill(-pid, SIGKILL);
        while (waitpid(pid, NULL, 0) < 0 && errno == EINTR)
        {
        }
        if (terminal_handed_off)
            (void)set_terminal_foreground_group(STDIN_FILENO, parent_foreground_group);
        os_process_free(process);
        process = NULL;
        goto fail;
    }
    return process;

fail:
    if (actions_initialized)
    {
        (void)posix_spawn_file_actions_destroy(&actions);
    }
    if (attributes_initialized)
    {
        (void)posix_spawnattr_destroy(&attributes);
    }
    close_fd(&stdin_pipe[0]);
    close_fd(&stdin_pipe[1]);
    close_fd(&stdout_pipe[0]);
    close_fd(&stdout_pipe[1]);
    close_fd(&stderr_pipe[0]);
    close_fd(&stderr_pipe[1]);
    close_fd(&cancel_pipe[0]);
    close_fd(&cancel_pipe[1]);
    *error_code = result;
    return NULL;
}

static int read_fd(os_process *process, int fd, void *buffer, int capacity)
{
    struct pollfd descriptors[2];
    ssize_t count;
    if (buffer == NULL || capacity <= 0)
        return -EINVAL;
    descriptors[0].fd = fd;
    descriptors[0].events = POLLIN | POLLHUP;
    descriptors[1].fd = process->cancel_read_fd;
    descriptors[1].events = POLLIN | POLLHUP;
    for (;;)
    {
        if (atomic_load(&process->io_cancelled))
            return 0;
        if (poll(descriptors, 2, -1) < 0)
        {
            if (errno == EINTR)
                continue;
            return -errno;
        }
        if (descriptors[1].revents != 0)
            return 0;
        do
        {
            count = read(fd, buffer, (size_t)capacity);
        } while (count < 0 && errno == EINTR);
        if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
            continue;
        return count < 0 ? -errno : (int)count;
    }
}

int os_process_read_stdout(os_process *process, void *buffer, int capacity)
{
    return process == NULL ? -EINVAL : read_fd(process, process->stdout_fd, buffer, capacity);
}

int os_process_read_stderr(os_process *process, void *buffer, int capacity)
{
    return process == NULL ? -EINVAL : read_fd(process, process->stderr_fd, buffer, capacity);
}

static int write_fd_without_sigpipe(os_process *process, int fd, const void *buffer, int capacity)
{
    sigset_t blocked;
    sigset_t old_mask;
    struct sigaction pipe_action;
    ssize_t count;
    int mask_error;
    int pipe_is_ignored;
    int saved_error;
    int ignored_signal;
    struct pollfd descriptors[2];

    if (buffer == NULL || capacity <= 0)
        return -EINVAL;
    if (sigemptyset(&blocked) != 0 || sigaddset(&blocked, SIGPIPE) != 0)
    {
        return -errno;
    }
    if (sigaction(SIGPIPE, NULL, &pipe_action) != 0)
        return -errno;
    pipe_is_ignored = pipe_action.sa_handler == SIG_IGN;
    mask_error = pthread_sigmask(SIG_BLOCK, &blocked, &old_mask);
    if (mask_error != 0)
        return -mask_error;
    descriptors[0].fd = fd;
    descriptors[0].events = POLLOUT | POLLHUP;
    descriptors[1].fd = process->cancel_read_fd;
    descriptors[1].events = POLLIN | POLLHUP;
    do
    {
        if (atomic_load(&process->io_cancelled))
            count = 0;
        else if (poll(descriptors, 2, -1) < 0)
            count = -1;
        else if (descriptors[1].revents != 0)
            count = 0;
        else
            count = write(fd, buffer, (size_t)capacity);
    } while (count < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK));
    saved_error = count < 0 ? errno : 0;
    if (saved_error == EPIPE && !pipe_is_ignored)
    {
        (void)sigwait(&blocked, &ignored_signal);
    }
    mask_error = pthread_sigmask(SIG_SETMASK, &old_mask, NULL);
    if (mask_error != 0)
        return -mask_error;
    if (saved_error == EPIPE)
        return 0;
    return count < 0 ? -saved_error : (int)count;
}

int os_process_write_stdin(os_process *process, const void *buffer, int capacity)
{
    if (process == NULL)
        return -EINVAL;
    if (process->stdin_fd < 0)
        return 0;
    return write_fd_without_sigpipe(process, process->stdin_fd, buffer, capacity);
}

void os_process_cancel_io(os_process *process)
{
    char byte = 0;
    if (process != NULL && !atomic_exchange(&process->io_cancelled, 1))
        (void)write(process->cancel_write_fd, &byte, 1);
}

int os_process_close_stdin(os_process *process)
{
    int fd;
    if (process == NULL)
        return EINVAL;
    if (process->stdin_fd < 0)
        return 0;
    fd = process->stdin_fd;
    process->stdin_fd = -1;
    return close(fd) == 0 ? 0 : errno;
}

int os_process_wait(os_process *process, int *exit_code)
{
    int status;
    pid_t result;
    if (process == NULL || exit_code == NULL)
        return EINVAL;
    if (process->has_exited)
    {
        *exit_code = process->exit_code;
        return 0;
    }
    do
    {
        result = waitpid(process->pid, &status, 0);
    } while (result < 0 && errno == EINTR);
    if (result < 0)
        return errno;
    process->exit_code = decoded_exit_code(status);
    process->has_exited = 1;
    *exit_code = process->exit_code;
    return 0;
}

static int elapsed_milliseconds(const struct timespec *started_at)
{
    struct timespec now;
    int64_t seconds;
    int64_t nanoseconds;
    int64_t milliseconds;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0)
        return INT_MAX;
    seconds = (int64_t)now.tv_sec - (int64_t)started_at->tv_sec;
    nanoseconds = (int64_t)now.tv_nsec - (int64_t)started_at->tv_nsec;
    milliseconds = seconds * 1000 + nanoseconds / 1000000;
    if (milliseconds < 0)
        return 0;
    return milliseconds > INT_MAX ? INT_MAX : (int)milliseconds;
}

int os_process_timeout_remaining(os_process *process, int timeout_milliseconds)
{
    int elapsed;
    if (process == NULL || timeout_milliseconds <= 0)
        return 0;
    elapsed = elapsed_milliseconds(&process->started_at);
    return elapsed >= timeout_milliseconds ? 0 : timeout_milliseconds - elapsed;
}

int os_process_wait_for(os_process *process, int timeout_milliseconds,
                        int *timed_out, int *exit_code)
{
    struct timespec pause = {0, 10000000};
    int status;
    pid_t result;
    if (process == NULL || timeout_milliseconds <= 0 || timed_out == NULL || exit_code == NULL)
        return EINVAL;
    *timed_out = 0;
    while (!process->has_exited)
    {
        do
        {
            result = waitpid(process->pid, &status, WNOHANG);
        } while (result < 0 && errno == EINTR);
        if (result < 0)
            return errno;
        if (result > 0)
        {
            process->exit_code = decoded_exit_code(status);
            process->has_exited = 1;
            break;
        }
        if (os_process_timeout_remaining(process, timeout_milliseconds) == 0)
        {
            *timed_out = 1;
            *exit_code = -1;
            return 0;
        }
        (void)nanosleep(&pause, NULL);
    }
    *exit_code = process->exit_code;
    return 0;
}

int os_process_restore_terminal(os_process *process)
{
    int result;
    if (process == NULL)
        return EINVAL;
    if (!process->terminal_handed_off)
        return 0;
    result = set_terminal_foreground_group(STDIN_FILENO, process->parent_foreground_group);
    if (result == 0)
        process->terminal_handed_off = 0;
    return result;
}

int os_process_terminate(os_process *process)
{
    int result;
    if (process == NULL)
        return EINVAL;
    /* SIGKILL gives terminate one deterministic meaning and prevents a direct
       child from handling a softer signal while leaving descendants alive. */
    result = kill(-process->pid, SIGKILL);
    return result == 0 || errno == ESRCH ? 0 : errno;
}

int os_process_force_terminate(os_process *process)
{
    int result;
    if (process == NULL)
        return EINVAL;
    result = kill(-process->pid, SIGKILL);
    return result == 0 || errno == ESRCH ? 0 : errno;
}

void os_process_free(os_process *process)
{
    if (process != NULL)
    {
        close_fd(&process->stdin_fd);
        close_fd(&process->stdout_fd);
        close_fd(&process->stderr_fd);
        close_fd(&process->cancel_read_fd);
        close_fd(&process->cancel_write_fd);
        free(process);
    }
}

#endif
