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

> [!WARNING]
> This library is currently being tested and its public API is still being
> refined to make it as convenient and useful as possible. Breaking changes
> should be expected.

## Features

- One API for EiffelStudio and Gobo Eiffel.
- Linux, macOS, and Windows support, continuously tested with both compilers.
- Synchronous process execution with captured standard output and error.
- Copied raw-byte standard input with EOF after the configured bytes.
- Asynchronous processes with streaming callbacks, status polling, waiting,
  and termination.
- Safe argument-vector execution that does not construct a shell command.
- An explicit shell helper for commands that require platform shell syntax.
- Per-command working directories with reusable configuration snapshots.
- Portable path composition, inspection, text I/O, directory creation, and
  recursive deletion.
- Void-safe interfaces with contracts and no compiler conditionals in client
  code.

The small public surface is organized around four classes:

| Class | Purpose |
| --- | --- |
| `OS_COMMAND` | Describes an executable and argument vector and starts independent executions |
| `OS_PROCESS` | Represents a running process and exposes its lifecycle and completed outcome |
| `OS_PROCESS_RESULT` | Holds the exit code, standard output, and standard error of a completed run |
| `OS_FILE_PATH` | Represents a path and provides common file and directory operations |

## Portability

Client code is identical across the supported compiler and operating-system
matrix:

| Toolchain | Linux | macOS | Windows | Process backend |
| --- | :---: | :---: | :---: | --- |
| EiffelStudio | ✓ | ✓ | ✓ | Eiffel threads over the native C11 bridge |
| Gobo Eiffel | ✓ | ✓ | ✓ | Eiffel threads over the native C11 bridge |

Both compilers deliberately use the same process backend. This removes
compiler-specific lifecycle and quoting behavior, and keeps process fixes and
tests on one implementation. It also makes the native library mandatory: every
consumer must build and distribute the platform-specific C archive, and new
platform support requires native implementation and CI coverage rather than an
Eiffel-only integration.

File-path operations use the common EiffelBase/FreeELKS `PATH`, `FILE_INFO`,
`DIRECTORY`, and file classes. They do not need a compiler-specific backend.

Platform differences remain explicit where they matter. `make_shell` uses
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

The same ECF reference and native backend are used by both compilers. Build the
C bridge before compiling a client. On Linux and macOS:

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

Create a command from the executable and its argument vector, then run it to
receive a typed result:

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

`OS_COMMAND` copies the executable and every argument when it is created, so it
can be reused for sequential or overlapping executions even if the caller later
modifies the original strings or collection. `run` passes the stored argument
vector directly to the child process. Spaces, quotes, backslashes, and empty
arguments do not require shell escaping.

If the executable or working directory cannot be used, `run` returns a result
with `was_launched` false and the conventional synthetic exit code 127. A child
that actually exits with code 127 has `was_launched` true, so the two cases are
unambiguous.

Set an optional working directory before starting the command:

```eiffel
create command.make ("git", << "status", "--short" >>)
command.set_working_directory ("/path/to/repository")
process_result := command.run
```

The command stores an absolute canonical snapshot of the directory when
`set_working_directory` is called. Changing the command later affects only
subsequent executions; an already created `OS_PROCESS` retains its original
directory.

Set standard input before starting the command:

```eiffel
create command.make ("tool", << "--read-stdin" >>)
command.set_input ("first line%Nsecond line%N")
process_result := command.run
```

`set_input` copies a `READABLE_STRING_8` as raw bytes. The child receives those
bytes followed by EOF; an unset or empty input produces immediate EOF. No text
encoding or newline conversion is applied by the library. As with the working
directory, changing the input affects only subsequent starts. Already started
processes retain their own snapshots, including when one command is started
more than once concurrently.

### Stream process output

Use `start` when output should be handled as it arrives or when the caller needs
control over the process lifecycle:

```eiffel
local
    command: OS_COMMAND
    process: OS_PROCESS
    process_result: OS_PROCESS_RESULT
do
    create command.make ("git", << "status", "--short" >>)
    process := command.start_with_handlers (
        agent on_stdout,
        agent on_stderr
    )
    process.wait
    process_result := process.outcome
end
```

The process provides `poll`, `is_finished`, `wait`, `terminate`, and `outcome`.
`poll` is a nonblocking command that advances process state; `is_finished` only
observes the state already recorded by `poll` or `wait`. For example:

```eiffel
local
    environment: EXECUTION_ENVIRONMENT
do
    create environment
    from
        process.poll
    until
        process.is_finished
    loop
        environment.sleep (1_000_000)
        process.poll
    end
    process_result := process.outcome
end
```

Every started process must be driven to completion through `wait` or repeated
`poll` calls. `terminate` only requests platform-dependent termination, so it
must also be followed by `wait` or polling. The library does not run an
automatic background reaper.

`is_finished` becomes true only after the child, both output readers, and the
input writer have finished and native resources have been released. Output
callbacks may run concurrently and should return quickly; ordering is preserved
within each stream, not between standard output and standard error. If a
callback raises an exception, that handler is disabled, all pipes are still
drained, and the failure is reported after cleanup by `poll`, `wait`, or
`outcome`.

Both streams are exposed as immutable snapshots through `READABLE_STRING_8`.
They contain raw bytes; the library does not impose an output encoding.

For commands that intentionally require a shell, use the separate helper:

```eiffel
create command.make_shell ("git --version")
process_result := command.run
```

Shell syntax is platform-dependent. Do not concatenate untrusted input into a
shell command; use `make` with an explicit argument vector instead.

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
compiler plus an archiver for the shared process backend.

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
advanced EiffelStudio-only features such as environment replacement, timeouts,
process trees, interactive incremental input, or detailed redirection control,
use the EiffelStudio `PROCESS` library directly.
