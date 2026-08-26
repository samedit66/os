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
| [`OS_COMMAND`](src/process/os_command.e) | Configure an executable, arguments, input, and working directory, then start independent executions |
| [`OS_PROCESS`](src/process/backend/native/os_process.e) | Poll, wait for, or terminate a running process |
| [`OS_PROCESS_RESULT`](src/process/os_process_result.e) | Inspect launch status, exit code, standard output, and standard error |
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

Reference it from the consuming project's ECF file:

```xml
<library name="os" location="./vendor/os/os.ecf" readonly="true"/>
```

The native process library is required by both Eiffel compilers. Build it on
Linux or macOS before compiling the client:

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
    process_result: OS_PROCESS_RESULT
do
    create command.make ("git", << "status", "--short" >>)
    process_result := command.run

    if process_result.successful then
        io.put_string (process_result.stdout)
    else
        io.error.put_string (process_result.stderr)
    end
end
```

`run` waits for completion, captures both output streams, and returns an
`OS_PROCESS_RESULT`. Its `successful` query is true only when the child was
launched and exited with code zero. The same command can start multiple
independent executions.

Set optional input or a working directory before calling `run` or `start`:

```eiffel
command.set_working_directory ("/path/to/repository")
command.set_input ("input bytes%N")
```

Use `start_with_handlers` to receive output while a process runs. See the
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
- `OS_COMMAND` keeps copied configuration, and each started process retains its
  own input and working-directory snapshots. Input and captured output are raw
  `READABLE_STRING_8` bytes; the library does not convert encodings or newlines.
  The child receives the configured input followed by EOF.
- Every process created by `start` or `start_with_handlers` must be completed
  with `wait` or repeated `poll` calls. `terminate` only requests termination
  and must also be followed by `wait` or polling.
- `is_finished` reports state recorded by `poll` or `wait`; `outcome` is
  available only after the process and its I/O workers have completed.
- Output callbacks may run concurrently. Ordering is preserved within each
  stream, but not between standard output and standard error.
- A launch failure produces `was_launched = False` and exit code `127`. A child
  that exits with the same code still has `was_launched = True`.

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
