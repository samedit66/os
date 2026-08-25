<div align="center">

# `os`

### Portable OS APIs for Eiffel

[![Language: Eiffel](https://img.shields.io/badge/language-Eiffel-6f42c1)](https://www.eiffel.org/)
[![ISE Eiffel](https://img.shields.io/badge/toolchain-ISE%20Eiffel-17365D)](https://www.eiffel.com/)
[![Gobo Eiffel](https://img.shields.io/badge/toolchain-Gobo%20Eiffel-8B5A2B)](https://www.gobosoft.com/)
[![Platforms](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-2f855a)](https://github.com/samedit66/os/actions/workflows/ci.yml)
[![CI](https://github.com/samedit66/os/actions/workflows/ci.yml/badge.svg)](https://github.com/samedit66/os/actions/workflows/ci.yml)

</div>

`os` is a void-safe Eiffel library that provides small, convenient APIs for
common operating-system tasks. The same public classes and the same `os.ecf`
configuration work with EiffelStudio and Gobo Eiffel on Linux, macOS, and
Windows.

The library currently covers process execution and file-system paths. Its main
goal is to hide compiler- and platform-specific machinery behind a compact API
without hiding the places where operating systems genuinely behave differently.

## Features

- One API for EiffelStudio and Gobo Eiffel.
- Linux, macOS, and Windows support, continuously tested with both compilers.
- Synchronous process execution with captured standard output and error.
- Asynchronous processes with streaming callbacks, status polling, waiting,
  and termination.
- Safe argument-vector execution that does not construct a shell command.
- An explicit shell helper for commands that require platform shell syntax.
- Portable path composition, inspection, text I/O, directory creation, and
  recursive deletion.
- Void-safe interfaces with contracts and no compiler conditionals in client
  code.

The small public surface is organized around four classes:

| Class | Purpose |
| --- | --- |
| `OS_PROCESS_RUNNER` | Starts a process or runs it to completion |
| `OS_PROCESS_HANDLE` | Exposes a running process, captured output, and lifecycle operations |
| `OS_PROCESS_RESULT` | Holds the exit code, standard output, and standard error of a completed run |
| `OS_FILE_PATH` | Represents a path and provides common file and directory operations |

## Portability

Client code is identical across the supported compiler and operating-system
matrix:

| Toolchain | Linux | macOS | Windows | Process backend |
| --- | :---: | :---: | :---: | --- |
| EiffelStudio | ✓ | ✓ | ✓ | EiffelStudio `PROCESS` library |
| Gobo Eiffel | ✓ | ✓ | ✓ | Eiffel threads over a small native C11 bridge |

File-path operations use the common EiffelBase/FreeELKS `PATH`, `FILE_INFO`,
`DIRECTORY`, and file classes. They do not need a compiler-specific backend.

Platform differences remain explicit where they matter. `shell` uses
`/bin/sh -c` on POSIX systems and `COMSPEC` (falling back to `cmd.exe`) with
`/D /S /C` on Windows. `terminate` maps to `SIGTERM` on POSIX and
`TerminateProcess` on Windows.

## Installation

Add `os` to an Eiffel project as a Git submodule:

```console
git submodule add https://github.com/samedit66/os.git vendor/os
git submodule update --init
```

Reference the library from the consuming project's ECF file:

```xml
<library name="os" location="./vendor/os/os.ecf" readonly="true"/>
```

The same ECF reference is used by both compilers. EiffelStudio selects its
`PROCESS` backend and needs no native library from this repository. Gobo selects
the native backend when `GOBO_EIFFEL=ge`; build its C bridge before compiling.
On Linux and macOS:

```console
make -C vendor/os native
```

On Windows, run the following from a Visual Studio developer command prompt:

```console
cd vendor\os
.github\scripts\build-windows-c.cmd msvc library
```

## Usage

### Run a process

Create a runner, pass the executable and its arguments separately, and receive
a typed result:

```eiffel
local
    runner: OS_PROCESS_RUNNER
    result: OS_PROCESS_RESULT
do
    create runner
    result := runner.run ("git", << "status", "--short" >>)

    if result.successful then
        io.put_string (result.stdout)
    else
        io.error.put_string (result.stderr)
    end
end
```

`run` passes the argument vector directly to the child process. Spaces, quotes,
backslashes, and empty arguments do not require shell escaping.

### Stream process output

Use `start` when output should be handled as it arrives or when the caller needs
control over the process lifecycle:

```eiffel
local
    runner: OS_PROCESS_RUNNER
    process: OS_PROCESS_HANDLE
do
    create runner
    process := runner.start (
        "git",
        << "status", "--short" >>,
        agent on_stdout,
        agent on_stderr
    )
    process.wait
end
```

The handle provides `is_finished`, `wait`, `terminate`, `exit_code`, `stdout`,
and `stderr`. Output callbacks may run concurrently and should return quickly;
ordering is preserved within each stream, not between standard output and
standard error. Both streams are exposed as raw `STRING_8` byte sequences; the
library does not impose an output encoding.

For commands that intentionally require a shell, use the separate helper:

```eiffel
result := runner.shell ("git --version")
```

Shell syntax is platform-dependent. Do not concatenate untrusted input into a
shell command; use `run` with an explicit argument vector instead.

### Work with paths

The path API keeps routine file-system work concise and portable:

```eiffel
local
    directory: OS_FILE_PATH
    file: OS_FILE_PATH
do
    create directory.make ("build/example")
    directory.create_directory

    file := directory / "message.txt"
    file.write_text ("Hello from os%N")
    io.put_string (file.read_text)
end
```

`OS_FILE_PATH` also provides `exists`, `is_directory`, `is_plain_file`,
`is_empty_directory`, `parent`, `canonical_path`, and `delete_recursively`.
Recursive deletion removes a symbolic link itself and never follows it to its
target.

## Building

Required tools are Gobo Eiffel 26.06, EiffelStudio 25.12 or later, and a C11
compiler plus an archiver for the Gobo process backend.

On Linux and macOS, build and run the example with Gobo Eiffel:

```console
make gobo
```

Build and run the same example with EiffelStudio:

```console
make ise
```

Tool locations can be overridden when necessary:

```console
make gobo GOBO=/path/to/gobo GEC=/path/to/gec GELINT=/path/to/gelint CC=clang
```

## Tests

On Linux and macOS, run the shared test suite with both compilers:

```console
make test
```

Or select one toolchain:

```console
make test-gobo
make test-ise
```

The tests are generated with Gobo Test and exercise the same process and path
behavior under both compilers. CI extends that matrix across Ubuntu, macOS, and
Windows. The native bridge is additionally compiled with GCC, Clang, MSVC, and
clang-cl.

## Scope

The process API deliberately focuses on the common portable workflow. For
advanced EiffelStudio-only features such as custom standard input, working
directories, environment replacement, timeouts, process trees, or detailed
redirection control, use the EiffelStudio `PROCESS` library directly.
