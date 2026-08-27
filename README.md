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
| [`OS_COMMAND`](src/process/os_command.e) | Configure and sequentially execute a command, including polling, waiting, and termination |
| [`OS_PROCESS_EXECUTION_RESULT`](src/process/os_process_execution_result.e) | Inspect launch status, optional exit code, captured output, and structured failures |
| [`OS_PROCESS_FAILURE`](src/process/os_process_failure.e) | Inspect one portable process-library failure and its optional native code |
| [`OS_FILE_PATH`](src/file_path/os_file_path.e) | Compose and inspect paths and perform common file and directory operations |

Both Eiffel compilers use the same native C11 process backend. The platform
implementations are in [`subprocess_posix.c`](c/subprocess_posix.c) and
[`subprocess_windows.c`](c/subprocess_windows.c). Path operations use the
common EiffelBase/FreeELKS file-system classes.

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
file and path operations can avoid the thread library, native archive, and C
toolchain by importing `file_path.ecf` directly:

```xml
<library name="os_file_path" location="./vendor/os/file_path.ecf" readonly="true"/>
```

Process-only clients can import `process.ecf`:

```xml
<library name="os_process" location="./vendor/os/process.ecf" readonly="true"/>
```

The process module and the complete package require the native process
library. Build it on Linux or macOS before compiling the client:

```console
make -C vendor/os native
```

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
an exit code of zero, and the library recorded no failures. One `OS_COMMAND`
can be executed again after its previous execution is finished.

Set optional input or a working directory before calling `run` or `start`:

```eiffel
command.set_working_directory ("/path/to/repository")
command.set_input ("input bytes%N")
```

`set_working_directory` accepts a `READABLE_STRING_GENERAL` and stores a
normalized absolute snapshot immediately. When using `OS_FILE_PATH`, pass its
name explicitly:

```eiffel
command.set_working_directory (directory.name)
```

This string-based parameter replaces the earlier direct `OS_FILE_PATH`
parameter so that the process module remains independent of the file-path
module.

Use `start_streaming` to receive output while a process runs, then call
`wait_for_exit`:

```eiffel
command.start_streaming (agent on_stdout, agent on_stderr)
command.wait_for_exit
```

For nonblocking progress checks, poll explicitly:

```eiffel
command.start
from
until
    command.finished
loop
    command.poll
end
```

`finished` is passive recorded state. A false value may be stale until `poll`
or `wait_for_exit` updates it; a true value remains true until the next start.
See the complete [streaming example](src/application.e).

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

`OS_FILE_PATH` also provides `exists`, `is_directory`, `is_plain_file`,
`is_empty_directory`, `parent`, `normalized_absolute_path`, `bytes`,
`write_bytes`, and `delete_recursively`. Recursive deletion removes a symbolic
link itself rather than following its target.

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
- Every execution created by `start` or `start_streaming` must reach completion
  through `wait_for_exit` or repeated `poll` calls. `terminate` only requests
  platform-dependent termination and must still be followed by waiting or
  polling. It does not promise graceful shutdown and affects only the immediate
  child, not its process tree.
- Garbage collection does not terminate or wait for an abandoned child. Client
  code must retain the command and guarantee `terminate`/`wait_for_exit` from
  its cleanup or rescue path.
- `execution_result` is available only after the child and all I/O workers have
  completed and native resources have been released.
- Output callbacks may run concurrently. Ordering is preserved within each
  stream, but not between standard output and standard error. Callback
  exceptions are contained and returned as structured failures; captured bytes
  remain available. Callbacks that mutate shared client state must provide their
  own synchronization and must not reenter lifecycle commands on the same
  `OS_COMMAND`.
- A launch failure produces `was_launched = False`, `has_exit_code = False`,
  and a launch failure value. A real child exit of `127` has
  `was_launched = True` and `has_exit_code = True`.
- Executable names, arguments, shell commands, and working directories reject
  embedded NUL characters. Standard input is a byte stream and may contain NUL.
- A descendant can inherit the stdout or stderr pipe. In that case the direct
  child may already have exited while `wait_for_exit` still waits for reader
  EOF.

The linked public classes contain the complete feature contracts and lifecycle
details.

## Development

Building requires Gobo Eiffel 26.06, EiffelStudio 25.12 or later, and a C11
compiler with an archiver. On Linux and macOS:

```console
make gobo       # build and run the example with Gobo Eiffel
make ise        # build and run the example with EiffelStudio
make test       # run the shared test suite with both compilers
```

Individual test targets and tool overrides are defined in the
[`Makefile`](Makefile). CI runs the shared suite on Ubuntu, macOS, and Windows.

## Scope

The process API focuses on common portable workflows. For features such as
environment replacement, timeouts, process trees, incremental interactive
input, or detailed redirection control, use the EiffelStudio `PROCESS` library
directly.
