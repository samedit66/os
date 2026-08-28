# `os` reference guide

This guide describes the behavior shared by EiffelStudio and Gobo Eiffel.
Public Eiffel classes and their contracts remain the source of truth for exact
feature signatures and preconditions.

## Package configuration

[`os.ecf`](../os.ecf) is the single public library configuration. It exposes
the process and file-path APIs, requires Eiffel thread support, and links the
native archive produced by `make native` on POSIX or `build-native.cmd` on
Windows.

The native implementations are combined in one C11 archive. Process
integration is in [`subprocess_posix.c`](../c/subprocess_posix.c) and
[`subprocess_windows.c`](../c/subprocess_windows.c). File-system operations
that require common cross-compiler semantics are in
[`file_path_posix.c`](../c/file_path_posix.c) and
[`file_path_windows.c`](../c/file_path_windows.c).

## Process execution

### Command construction

[`OS_COMMAND`](../src/process/os_command.e) represents reusable command
configuration and at most one active execution.

`make` accepts an executable and argument vector. Arguments are passed directly
to the child and do not need shell escaping. `make_shell` selects the platform
shell for a command that genuinely needs shell syntax; untrusted input must not
be concatenated into that string.

Executable names, arguments, shell commands, and working directories reject
embedded NUL characters.

### Lifecycle

Choose an execution mode according to how the caller needs to synchronize:

- `run` starts the process and waits for the final result;
- `start` starts it without callbacks and returns immediately;
- `start_streaming` starts it with optional output callbacks and returns
  immediately;
- `wait_for_exit` waits for an already started execution;
- `terminate` forcefully terminates the managed process tree.

`finished` becomes true autonomously after native waiting, I/O cleanup, and
result publication. Polling is not required to make progress. `execution_result`
is available only when `finished` is true.

Executions cannot overlap on one command. Configuration can be changed and the
command can be started again only when `can_start` is true. Configuration is
retained between sequential executions.

Every execution owns a POSIX process group or Windows Job Object. `terminate`
is idempotent, forceful rather than graceful, and does not require a later
`wait_for_exit`. On POSIX, a descendant that deliberately creates a new session
or process group can escape containment. Windows breakaway is disabled, so
descendants remain in the Job Object.

### Standard streams

The defaults are:

- stdin: an empty pipe followed by EOF;
- stdout: captured;
- stderr: captured separately.

`set_input` supplies copied raw bytes and selects piped stdin. `inherit_stdin`
connects the child to the inherited input without creating an Eiffel writer.

For each output stream, select capture, inheritance, or discard. Inherited and
discarded bytes are not buffered in Eiffel memory. `merge_stderr` redirects
stderr to the configured stdout destination. If stdout is captured, merged
bytes appear in `execution_result.stdout`; no separate stderr snapshot exists.
Check `stdout_was_captured`, `stderr_was_captured`, and `stderr_was_merged`
before reading conditional fields.

Input and captured output are `READABLE_STRING_8` byte streams. The process
module does not convert encodings or newlines.

On POSIX, synchronous `run` can temporarily give inherited terminal stdin to
the child process group and restores the foreground group afterward.
Asynchronous `start` and `start_streaming` reject inherited terminal stdin but
accept inherited nonterminal input. The library does not create a PTY.

### Streaming callbacks

`start_streaming` can receive agents for captured stdout and stderr. Callbacks
may run concurrently. Ordering is preserved within each stream, but not between
stdout and stderr.

A callback executes on its stream worker and must eventually return. It must
not reenter lifecycle commands on the same `OS_COMMAND`. If it mutates shared
client state, the client must provide synchronization.

Callback exceptions are contained and reported as structured failures;
captured bytes remain available.

### Deadlines and descendants

`set_timeout_milliseconds` sets an overall execution deadline. It covers the
direct process and I/O completion, including descendants that inherited a
capture pipe. `clear_timeout` restores unlimited execution.

On expiration, the managed process tree is killed, pipes receive a one-second
drain grace, and remaining native I/O is cancelled. `was_timed_out` identifies
the result. `output_was_cut_off` indicates that a captured stream did not reach
EOF during the grace period.

Without a deadline, a descendant that retains a capture pipe can keep an
execution unfinished after the direct child exits.

### Environment and executable lookup

Each command owns an [`OS_ENVIRONMENT`](../src/process/os_environment.e)
snapshot copied from the current application at command creation. Mutations do
not affect the parent application.

Use `set_environment_variable`, `unset_environment_variable`,
`clear_environment`, and `prepend_to_path` to configure subsequent executions.
`clear_environment` does not reinsert `PATH` or Windows `SystemRoot`.

Names reject NUL and `=`. Values reject NUL but may be empty; an empty value is
distinct from an absent variable. Names are case-sensitive on Unix and
case-insensitive on Windows.

The effective environment `PATH` is used both to resolve a bare executable and
as the value seen by the child. Removing `PATH` disables lookup of bare names;
it does not fall back to the parent environment. Explicit paths remain usable.
Relative `PATH` entries are resolved against the command's configured working
directory.

Use `has_executable` to test resolution and `executable_path` to obtain an
absolute normalized path without starting a process.

Unix separates `PATH` entries with `:` and requires candidates to be plain
files executable by the current process. Windows uses `;`, requires plain
files, and also tries `.exe` for an extensionless name. Final Windows image
validation remains the responsibility of `CreateProcessW`.

`set_working_directory` stores a normalized absolute snapshot immediately. To
use an `OS_FILE_PATH`, pass its `name`; this string boundary keeps the process
module independent of the file-path module.

### Execution results and failures

[`OS_PROCESS_EXECUTION_RESULT`](../src/process/os_process_execution_result.e)
contains launch state, optional exit code, stream metadata, captured bytes,
termination state, and structured failures.

`successful` is true only when the child was launched, has exit code zero, was
not terminated or timed out, and the library recorded no failures.

A launch failure has `was_launched = False` and `has_exit_code = False`. A real
child exit with code 127 has both values true and retains 127 as its exit code.
A nonzero child exit is not itself an `OS_PROCESS_FAILURE`.

[`OS_PROCESS_FAILURE`](../src/process/os_process_failure.e) describes a
portable failure category, operation, message, and optional native error code.
Failures can describe launch, stream, supervision, callback, and client-side
errors independently of a child exit status.

## File paths

[`OS_FILE_PATH`](../src/file_path/os_file_path.e) is a value object for a native
path. `make` copies a string representation, and `make_from_path` accepts an
Eiffel `PATH`. `name`, `parent`, and `normalized_absolute_path` provide common
path observations. The `/` operator appends a nonempty relative name.

### Status and traversal

Status queries include `exists`, `is_directory`, `is_plain_file`,
`is_symbolic_link`, `is_empty_directory`, `size`, and `is_executable`.

`entries` returns a snapshot of direct children. `glob` matches direct child
names, while `glob_recursive` matches descendant names without following
directory symlinks below the root.

The portable pattern syntax is intentionally limited to case-sensitive `*` and
`?`. Separators, `**`, character classes, and escapes are not supported.

### Content and encodings

`bytes` and `write_bytes` read and write raw bytes. `text` and `write_text` use
strict UTF-8 without automatic byte-order-mark detection. Invalid UTF-8 raises
a conversion failure.

For another character set, pass an explicit `ENCODING` to
`text_with_encoding` or `write_text_with_encoding`. Invalid source input and
characters that cannot be represented in the target encoding raise an
exception.

### File-system changes

`create_directory` creates missing parents and does nothing when the directory
already exists. `set_executable` adds the owner execute bit on POSIX and is an
idempotent no-op on Windows.

`copy_to` copies a plain non-symlink file and may replace a plain non-symlink
target. An I/O failure may leave a partial target.

`rename_to` requires an absent destination and uses the native rename operation;
it does not fall back to copying across file systems. The source object's
stored `name` does not change.

`replace_with` renames a plain source file over an absent file, plain file, or
symbolic link. It also does not copy across file systems. A symbolic-link target
is replaced rather than followed.

`delete_recursively` deletes a path if it exists. Directory symlinks and other
symbolic links are removed without following their targets.

Consult the contracts on each feature before an operation: they distinguish
absent paths, plain files, directories, and symbolic links deliberately.

## Platform and compatibility boundary

The public classes, contracts, ECF configurations, and documented behavior are
shared by EiffelStudio and Gobo Eiffel on Linux, macOS, and Windows. Native
process and file-system details remain behind the C backends.

The library targets portable workflows rather than emulating every platform
facility. Incremental interactive stdin, PTYs, file-backed redirection,
graceful signal protocols, and child-PID enumeration are outside its scope.
