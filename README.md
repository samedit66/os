# os

`os` is a portable Eiffel library for common operating-system operations.
`os.ecf` is its only ECF configuration and exposes process and file-path APIs.

Applications reference `os.ecf` directly:

```xml
<library name="os" location="path/to/os.ecf"/>
```

The configuration contains four targets: the `os` library target, the
`application` example, `os_process_tests`, and `os_file_path_tests`. It does not
reference nested project libraries; compiler-specific dependencies and backend
clusters are selected directly by `os.ecf`.

The library has four public classes:

- `OS_PROCESS_RUNNER` starts and runs programs;
- `OS_PROCESS_HANDLE` represents a running or completed program;
- `OS_PROCESS_RESULT` contains the result of a synchronous run;
- `OS_FILE_PATH` represents a file-system path and provides common file and
  directory operations.

## File-path API

Create a directory, extend its path, and write and read a text file:

```eiffel
create directory.make ("build/example")
directory.create_directory
file := directory / "message.txt"
file.write_text ("Hello from os%N")
io.put_string (file.read_text)
```

`OS_FILE_PATH.make` accepts a path name, while `make_from_path` accepts an
existing Eiffel `PATH`. The `/` operator appends a nonempty relative path.
`parent` and `canonical_path` return new `OS_FILE_PATH` objects without changing
the original path.

`create_directory` creates missing parents and is a no-op for an existing
directory. `write_text` replaces a plain file with UTF-8 encoded text;
`read_text` returns its complete encoded bytes as a `STRING_8`.

`delete_recursively` is a no-op for a missing entry. It deletes directory trees,
plain files, and symbolic links. A symbolic link itself is deleted without
traversing or deleting its target, including when the target does not exist.

The path implementation is shared by EiffelStudio and Gobo through the common
EiffelBase/FreeELKS `PATH`, `FILE_INFO`, `DIRECTORY`, and file classes; it does
not require compiler-specific backends.

## Process API

Run an executable synchronously with an explicit argument vector:

```eiffel
create runner
result := runner.run ("git", << "status", "--short" >>)
io.put_string (result.stdout)
```

Start it asynchronously and receive output as it arrives:

```eiffel
process := runner.start (
    "git",
    << "status", "--short" >>,
    agent on_stdout,
    agent on_stderr
)
process.wait
```

Run a command through the platform shell:

```eiffel
result := runner.shell ("git --version")
```

`run` and `start` pass arguments directly to the child process and never
construct a shell command. This preserves spaces, quotes, backslashes, and empty
arguments without shell escaping.

`shell` deliberately has different semantics: POSIX uses `/bin/sh -c`, while
Windows uses `COMSPEC` (or `cmd.exe` when it is unavailable) with `/D /S /C`.
Shell syntax is platform-dependent. Never construct a shell command by
concatenating untrusted input; use `run` with an explicit argument vector
instead.

`stdout` and `stderr` are raw 8-bit byte chunks. No encoding conversion is
performed on child output.

Callbacks for the two streams may run concurrently, preserve order only within
their own stream, and should return quickly. Callback failures are remembered
while both pipes continue to drain and are raised by `wait` after the child and
readers complete. Complete captured output is available after `wait`; reading
it while the process is running is unspecified.

`terminate` requests termination. POSIX sends `SIGTERM`; Windows uses
`TerminateProcess`, so exact semantics are platform-dependent.

## Why use the process API

### EiffelStudio

EiffelStudio's `PROCESS` library is feature-rich, but a common captured run
requires a factory, a launcher, output/error redirection, launch, wait, and
manual result storage. `OS_PROCESS_RUNNER.run` reduces that workflow to one
operation returning an `OS_PROCESS_RESULT`; `start` provides the same compact
API for asynchronous work.

The process API is an ergonomic portable facade, not a replacement for advanced
`PROCESS` features. Use `PROCESS` directly when stdin, a working directory,
environment customization, timeouts, process trees, or detailed redirection
control are required.

### Gobo Eiffel

Gobo's `EXECUTION_ENVIRONMENT` provides string-based `system` and `launch`
operations. The process API adds a structured argument vector, captured stdout and
stderr, streaming callbacks, a process handle, wait, status polling, and
termination. Direct `run` and `start` also avoid the shell entirely.

## Implementations

The public API is shared, while the implementation is selected at compile time:

| Compiler | Backend | Process implementation |
| --- | --- | --- |
| EiffelStudio | ISE backend | EiffelStudio `PROCESS` |
| Gobo Eiffel | native backend | Eiffel threads over a native C bridge |

`native` describes the process mechanism rather than promising a
compiler-independent backend selection. The current ECF selects it for Gobo
with `GOBO_EIFFEL=ge`; EiffelStudio uses the ISE backend.

## Build and test

Required tools:

- Gobo Eiffel 26.06.30 (`GOBO` points to its distribution; the Makefile
  defaults to `$HOME/Projects/gobo`);
- EiffelStudio 25.02 or later (`ec` on `PATH`);
- a C11 compiler and archiver for the native backend.

```sh
make gobo
make ise
make test-gobo
make test-ise
make test
```

Override tool locations when needed:

```sh
make gobo GEC=/path/to/gec GELINT=/path/to/gelint CC=clang
```

The test commands run both the process and file-path suites. GitHub Actions has
separate matrices for native C compilation, Gobo behavior on
Ubuntu/macOS/Windows, and EiffelStudio behavior on Ubuntu/macOS/Windows. The C
bridge is compiled with GCC, Clang, MSVC, and clang-cl.

## Scope

Version 1 of the process API has no working-directory or environment
configuration, stdin control, timeout, asynchronous shell helper, or separate
hard-kill operation.
