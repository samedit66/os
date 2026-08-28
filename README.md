<div align="center">

# `os`

### Portable process and file-system APIs for Eiffel

[![Language: Eiffel](https://img.shields.io/badge/language-Eiffel-6f42c1)](https://www.eiffel.org/)
[![ISE Eiffel](https://img.shields.io/badge/toolchain-ISE%20Eiffel-17365D)](https://www.eiffel.com/)
[![Gobo Eiffel](https://img.shields.io/badge/toolchain-Gobo%20Eiffel-8B5A2B)](https://www.gobosoft.com/)
[![Platforms](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-2f855a)](https://github.com/samedit66/os/actions/workflows/ci.yml)
[![CI](https://github.com/samedit66/os/actions/workflows/ci.yml/badge.svg)](https://github.com/samedit66/os/actions/workflows/ci.yml)

</div>

`os` is a void-safe Eiffel library for portable process execution and common
file-system operations. It provides the same public API to EiffelStudio and
Gobo Eiffel on Linux, macOS, and Windows.

Use it when an application needs to:

- run a program without constructing a shell command;
- capture, stream, inherit, discard, or merge its standard streams;
- configure its environment, working directory, and execution deadline;
- compose paths and perform common file and directory operations.

> [!WARNING]
> The library is still being tested and its public API is being refined.
> Breaking changes should be expected.

## Installation

Add the repository to an Eiffel project. A Git submodule keeps the selected
library revision explicit:

```console
git submodule add https://github.com/samedit66/os.git vendor/os
git submodule update --init
```

Reference the package from the consuming project's ECF file:

```xml
<library name="os" location="./vendor/os/os.ecf" readonly="true"/>
```

The library requires Eiffel thread support. Enable it in the consuming target:

```xml
<capability>
    <concurrency support="thread" use="thread"/>
</capability>
```

On Linux and macOS, ensure that `make`, a C11 compiler, and an archiver are on
`PATH`, then build the native archive before compiling the Eiffel project:

```console
make -C vendor/os native
```

This produces `vendor/os/build/native/libos_native.a`. Set `CC` or `AR` when
the default `cc` and `ar` commands are not appropriate.

On Windows, run the native build from a regular Command Prompt. The script
locates an installed Visual Studio C++ toolchain and produces
`vendor\os\build\native\os_native.lib`:

```console
vendor\os\build-native.cmd
```

## Quick start

Create a command with an explicit argument vector, run it, and inspect its
result:

```eiffel
local
    command: OS_COMMAND
    process_result: OS_PROCESS_EXECUTION_RESULT
do
    create command.make ("git", <<"--version">>)
    command.set_timeout_milliseconds (5_000)
    command.run
    process_result := command.execution_result

    if process_result.successful then
        io.put_string (process_result.stdout)
    else
        across process_result.failures as failure loop
            io.error.put_string (failure.description)
            io.error.put_new_line
        end
    end
end
```

`OS_COMMAND.make` passes its arguments directly to the child; they do not need
shell escaping. Standard output and error are captured by default, and `run`
waits until the execution result is available.

Continue with the [getting-started tutorial](docs/tutorial.md), which covers
installation, process results, timeouts, environments, and file paths. See the
[reference guide](docs/reference.md) for lifecycle guarantees, stream modes,
failure semantics, and platform-specific behavior. The
[process API comparison](docs/comparison.md) explains where `OS_COMMAND` is
stronger than the EiffelStudio and Gobo alternatives and where it currently
has fewer capabilities. The complete tutorial program is in
[`examples/quick_start`](examples/quick_start).

## Public API

| Class | Purpose |
| --- | --- |
| [`OS_COMMAND`](src/process/os_command.e) | Configure and execute a command |
| [`OS_ENVIRONMENT`](src/process/os_environment.e) | Store an environment snapshot and resolve executables through `PATH` |
| [`OS_PROCESS_EXECUTION_RESULT`](src/process/os_process_execution_result.e) | Inspect launch state, exit status, captured output, and failures |
| [`OS_PROCESS_FAILURE`](src/process/os_process_failure.e) | Inspect a structured process-library failure |
| [`OS_FILE_PATH`](src/file_path/os_file_path.e) | Compose paths and perform file and directory operations |

The Eiffel classes and their contracts are the source of truth for individual
feature signatures and preconditions. The reference guide explains how those
features work together.

## Scope

The process API focuses on common portable workflows. It deliberately does not
provide incremental interactive input, PTYs, file-backed redirection, graceful
signal protocols, or child-PID enumeration. Use a platform-specific process
library when one of those capabilities is required.

## Development

Building requires Gobo Eiffel 26.06, EiffelStudio 25.12 or later, and a C11
compiler with an archiver. The main development commands are:

```console
make gobo       # build and run the quick-start example with Gobo Eiffel
make ise        # build and run the quick-start example with EiffelStudio
make test       # run the shared suite with both compilers
make check      # run gelint and the EiffelStudio Code Analyzer
make format     # format tracked Eiffel sources with gedoc
make ccheck     # analyze the handwritten C bridge with clang-tidy
make cformat    # format the handwritten C bridge with clang-format
```

CI runs the shared test suite on Ubuntu, macOS, and Windows.
