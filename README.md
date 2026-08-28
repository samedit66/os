<div align="center">

# `os`

### Portable OS APIs for Eiffel

[![Language: Eiffel](https://img.shields.io/badge/language-Eiffel-6f42c1)](https://www.eiffel.org/)
[![ISE Eiffel](https://img.shields.io/badge/toolchain-ISE%20Eiffel-17365D)](https://www.eiffel.com/)
[![Gobo Eiffel](https://img.shields.io/badge/toolchain-Gobo%20Eiffel-8B5A2B)](https://www.gobosoft.com/)
[![Platforms](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-2f855a)](https://github.com/samedit66/os/actions/workflows/ci.yml)
[![CI](https://github.com/samedit66/os/actions/workflows/ci.yml/badge.svg)](https://github.com/samedit66/os/actions/workflows/ci.yml)

</div>

`os` is a void-safe Eiffel library for running processes and working with
file-system paths. Its public API and [`os.ecf`](os.ecf) configuration work
with EiffelStudio and Gobo Eiffel on Linux, macOS, and Windows.

> [!WARNING]
> The library is still being tested and its public API is being refined.
> Breaking changes should be expected.

## API

| Class | Purpose |
| --- | --- |
| [`OS_COMMAND`](src/process/os_command.e) | Configure and sequentially execute a command, including standard I/O, deadlines, waiting, and tree termination |
| [`OS_ENVIRONMENT`](src/process/os_environment.e) | Store a copied environment and resolve executables through its `PATH` |
| [`OS_PROCESS_EXECUTION_RESULT`](src/process/os_process_execution_result.e) | Inspect launch status, optional exit code, captured output, and structured failures |
| [`OS_PROCESS_FAILURE`](src/process/os_process_failure.e) | Inspect one portable process-library failure and its optional native code |
| [`OS_FILE_PATH`](src/file_path/os_file_path.e) | Compose and inspect paths and perform common file and directory operations |

Both Eiffel compilers use the same native C11 backends. Process integration is
implemented in [`subprocess_posix.c`](c/subprocess_posix.c) and
[`subprocess_windows.c`](c/subprocess_windows.c); file-system operations that
need stable cross-compiler semantics are implemented in
[`file_path_posix.c`](c/file_path_posix.c) and
[`file_path_windows.c`](c/file_path_windows.c).

## Installation

Add the library to an Eiffel project as a Git submodule:

```console
git submodule add https://github.com/samedit66/os.git vendor/os
git submodule update --init
```

Reference the complete package from the consuming project's ECF file:

```xml
<library name="os" location="./vendor/os/os.ecf" readonly="true"/>
```

The umbrella configuration imports both public modules. Clients that need only
file and path operations can avoid the thread library and process backend by
importing `file_path.ecf` directly:

```xml
<library name="os_file_path" location="./vendor/os/file_path.ecf" readonly="true"/>
```

Process-only clients can import `process.ecf`:

```xml
<library name="os_process" location="./vendor/os/process.ecf" readonly="true"/>
```

The public modules use separate native archives. Build both on Linux or macOS
before compiling the complete package:

```console
make -C vendor/os native
```

For a single module, use `native-file-path` or `native-process` instead.

On Windows, use a Visual Studio developer command prompt:

```console
cd vendor\os
.github\scripts\build-windows-c.cmd msvc library
```

## Quick start

Run a process with an explicit argument vector and inspect its result:

```eiffel
local
    command: OS_COMMAND
    process_result: OS_PROCESS_EXECUTION_RESULT
do
    create command.make ("git", << "status", "--short" >>)
    command.run
    process_result := command.execution_result

    if process_result.successful then
        io.put_string (process_result.stdout)
    else
        io.error.put_string (process_result.stderr)
        across process_result.failures as failure loop
            io.error.put_string (failure.description)
            io.error.put_new_line
        end
    end
end
```

`run` waits for completion and records an `OS_PROCESS_EXECUTION_RESULT` in
`execution_result`. `successful` is true only when the child was launched, has
an exit code of zero, was not terminated or timed out, and the library recorded
no failures. One `OS_COMMAND` can be executed again after its previous execution
is finished.

Set optional input or a working directory before calling `run` or `start`:

```eiffel
command.set_working_directory ("/path/to/repository")
command.set_input ("input bytes%N")
```

Standard input is an empty pipe by default, while standard output and error are
captured. Each stream can instead be inherited or discarded without buffering
it in Eiffel memory:

```eiffel
command.inherit_stdin
command.inherit_stdout
command.discard_stderr
```

Use `capture_stdout` or `capture_stderr` to switch an output stream back to
capture. `set_input` switches stdin back to a pipe. `merge_stderr` redirects
stderr to the selected stdout destination; when stdout is captured, both
streams appear in `execution_result.stdout` and no separate stderr snapshot
exists. Check `stdout_was_captured`, `stderr_was_captured`, and
`stderr_was_merged` before reading conditional result fields.

On POSIX, synchronous `run` can hand inherited terminal stdin to the child
process group and restores the foreground group afterward. Asynchronous
`start` and `start_streaming` reject inherited terminal stdin, but accept an
inherited nonterminal stream. The library does not create a PTY.

Each command also owns an environment snapshot. Change it without modifying the
environment of the current application:

```eiffel
command.set_environment_variable ("ISE_EIFFEL", ise_path)
command.unset_environment_variable ("GIT_DIR")
command.prepend_to_path (toolchain_bin)
```

`prepend_to_path` keeps the remaining inherited `PATH` while giving the new
directory lookup priority. Use `clear_environment` when the child should receive
no inherited variables. The library does not reinsert `PATH` or `SystemRoot`
after clearing.

The same effective `PATH` is used both to resolve a bare executable and as the
value seen by the child. This is deliberately consistent across platforms:
native Windows `CreateProcessW` would otherwise search using the parent process
environment rather than the environment block supplied to the child.

Check or inspect resolution without starting the command:

```eiffel
if command.has_executable ("ec") then
    io.put_string (command.executable_path ("ec"))
end
```

`executable_path` returns an absolute normalized path. Removing `PATH` disables
lookup of bare executable names; it does not fall back to the parent `PATH`.
Explicit paths remain usable. Relative `PATH` entries are interpreted against
the command's configured working directory.

`set_working_directory` accepts a `READABLE_STRING_GENERAL` and stores a
normalized absolute snapshot immediately. When using `OS_FILE_PATH`, pass its
name explicitly:

```eiffel
command.set_working_directory (directory.name)
```

This string-based parameter replaces the earlier direct `OS_FILE_PATH`
parameter so that the process module remains independent of the file-path
module.

Use `start_streaming` to receive captured output while a process runs. Call
`wait_for_exit` when the current control flow needs to synchronize with the
result:

```eiffel
command.start_streaming (agent on_stdout, agent on_stderr)
command.wait_for_exit
```

Supervision is autonomous. `finished` becomes true after native waiting, I/O
cleanup, and result publication; it does not need a poll call:

```eiffel
command.start
-- Later, from the application's event loop:
if command.finished then
    process_result := command.execution_result
end
```

Configure an overall execution deadline in milliseconds when needed:

```eiffel
command.set_timeout_milliseconds (30_000)
command.run
if command.execution_result.was_timed_out then
    io.error.put_string ("command timed out%N")
end
```

`clear_timeout` restores unlimited execution. A deadline covers both the direct
process and I/O completion, including a descendant that inherited a capture
pipe. On expiration the process tree is killed, pipes receive a one-second drain
grace, and any remaining native I/O is cancelled. `output_was_cut_off` records
whether a captured stream failed to reach EOF during that grace. See the
complete [streaming example](src/application.e).

Work with paths through the same portable API:

```eiffel
local
    directory: OS_FILE_PATH
    file: OS_FILE_PATH
do
    create directory.make ("build/example")
    directory.create_directory

    file := directory / "message.txt"
    file.write_text ("Hello from os%N")
    io.put_string (file.text)
end
```

`OS_FILE_PATH` also provides status and metadata queries (`exists`,
`is_directory`, `is_plain_file`, `is_symbolic_link`, `is_empty_directory`,
`size`, and `is_executable`), snapshot traversal (`entries`, `glob`, and
`glob_recursive`), byte and encoded-text access, and native `copy_to`,
`rename_to`, and `replace_with` operations. `set_executable` adds the owner
execute bit on POSIX and is an idempotent no-op on Windows.

`glob` matches direct child names; `glob_recursive` matches descendant names
without following directory symlinks below its root. Their portable pattern
syntax deliberately contains only case-sensitive `*` and `?`; separators,
`**`, character classes, and escapes are not supported.

`rename_to` requires an absent destination and does not fall back to copying
between file systems. `replace_with` replaces an absent file, plain file, or
symbolic link with a plain source file. Recursive deletion and replacement both
operate on a symbolic link itself rather than following its target.

`text` and `write_text` use strict UTF-8 without automatic byte-order-mark
detection. Use an explicit `ENCODING` for another character set:

```eiffel
file.write_text_with_encoding ("Hello", {SYSTEM_ENCODINGS}.iso_8859_1)
io.put_string (file.text_with_encoding ({SYSTEM_ENCODINGS}.iso_8859_1))
```

Invalid input and characters that cannot be represented in the selected
encoding raise an exception. Use `bytes` and `write_bytes` when contents are
not text.

## Important behavior

- `OS_COMMAND.make` passes an argument vector directly to the child process;
  arguments do not need shell escaping.
- `make_shell` is available for platform shell syntax. Do not concatenate
  untrusted input into a shell command.
- `OS_COMMAND` keeps copied configuration between sequential executions. Input
  and captured output are raw
  `READABLE_STRING_8` bytes; the library does not convert encodings or newlines.
  The child receives the configured input followed by EOF.
- `start`, `run`, and `start_streaming` cannot overlap on one command. A new
  execution is allowed only when `can_start` is true.
- Every execution owns a POSIX process group or Windows Job Object. `terminate`
  forcefully kills that managed tree and returns without requiring a later
  `wait_for_exit`; the autonomous supervisor still reaps and publishes the
  result. Termination is idempotent and is not a graceful-shutdown request.
- On POSIX, a descendant that deliberately calls `setsid` or moves to another
  process group escapes this guarantee. Windows descendants remain in the Job
  Object because breakaway is not enabled.
- The command retains its current process until autonomous cleanup completes.
  Clients need `wait_for_exit` only when they must synchronize before continuing.
- `execution_result` is available only after the child and all I/O workers have
  completed and native resources have been released.
- Output callbacks may run concurrently. Ordering is preserved within each
  stream, but not between standard output and standard error. Callback
  exceptions are contained and returned as structured failures; captured bytes
  remain available. Callbacks that mutate shared client state must provide their
  own synchronization and must not reenter lifecycle commands on the same
  `OS_COMMAND`. Every callback must eventually return: it runs on its stream
  worker, and completion necessarily waits for that worker.
- A launch failure produces `was_launched = False`, `has_exit_code = False`,
  and a launch failure value. A real child exit of `127` has
  `was_launched = True` and `has_exit_code = True`.
- Executable names, arguments, shell commands, and working directories reject
  embedded NUL characters. Standard input is a byte stream and may contain NUL.
- Environment names reject NUL and `=`; values reject NUL but may be empty. An
  empty value is distinct from an unset variable. Names are case-sensitive on
  Unix and case-insensitive on Windows.
- Executable lookup separates `PATH` entries with `:` on Unix and `;` on
  Windows. Unix candidates must be plain files executable by the current
  process. Windows candidates must be plain files and an extensionless name is
  also tried with `.exe`; final image validation remains the responsibility of
  `CreateProcessW`.
- A descendant can inherit a captured stdout or stderr pipe. The execution is
  not finished until that pipe reaches EOF, even if the direct child exited;
  configure a timeout when descendant lifetime is not otherwise bounded.

The linked public classes contain the complete feature contracts and lifecycle
details.

## Development

Building requires Gobo Eiffel 26.06, EiffelStudio 25.12 or later, and a C11
compiler with an archiver. Code-quality targets additionally require
`clang-format` and `clang-tidy`. On Linux and macOS:

```console
make gobo       # build and run the example with Gobo Eiffel
make ise        # build and run the example with EiffelStudio
make test       # run the shared test suite with both compilers
make test-ise-finalized  # run the EiffelStudio suite as a finalized build
make check      # run gelint and the EiffelStudio Code Analyzer
make format     # format tracked Eiffel sources with gedoc
make ccheck     # analyze the handwritten C bridge with clang-tidy
make cformat    # format the handwritten C bridge with clang-format
```

Source lists, ECF targets, compiler flags, individual test targets, and tool
paths can be overridden through variables defined in the [`Makefile`](Makefile).
CI runs the shared suite on Ubuntu, macOS, and Windows.

## Scope

The process API focuses on common portable workflows. For features such as
incremental interactive input, PTYs, file-backed redirection, graceful signal
protocols, or enumeration of child PIDs, use a platform-specific process
library directly.
