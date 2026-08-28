# Getting started with `os`

This tutorial connects `os` to an Eiffel application, runs a process, handles
its result, and performs a small file-system operation.

## 1. Add the library

Add `os` at a stable path inside the application repository:

```console
git submodule add https://github.com/samedit66/os.git vendor/os
git submodule update --init
```

Reference it from the application ECF file:

```xml
<library name="os" location="./vendor/os/os.ecf" readonly="true"/>
```

The process API uses Eiffel threads, so the consuming target must enable them:

```xml
<capability>
    <concurrency support="thread" use="thread"/>
    <void_safety support="all" use="all"/>
</capability>
```

Build the native backends before compiling the Eiffel application:

```console
make -C vendor/os native
```

On Windows, run the equivalent build from a regular Command Prompt:

```console
vendor\os\build-native.cmd
```

## 2. Run a command

`OS_COMMAND` accepts an executable name and an argument vector. It does not
join the arguments into a shell command:

```eiffel
local
    command: OS_COMMAND
do
    create command.make ("git", <<"--version">>)
    command.run
end
```

The bare name `git` is resolved through the command's environment snapshot.
`run` starts the child and waits until process supervision, stream I/O, and
result publication have all completed.

Use `make_shell` only when shell syntax is actually required. Never concatenate
untrusted input into a shell command.

## 3. Inspect the result

After `run`, read `execution_result`:

```eiffel
local
    process_result: OS_PROCESS_EXECUTION_RESULT
do
    process_result := command.execution_result
    if process_result.successful then
        io.put_string (process_result.stdout)
    else
        if process_result.stderr_was_captured then
            io.error.put_string (process_result.stderr)
        end
        across process_result.failures as failure loop
            io.error.put_string (failure.description)
            io.error.put_new_line
        end
    end
end
```

`successful` means all of the following:

- the child was launched;
- it produced an exit code of zero;
- it was neither terminated by the client nor timed out;
- the library recorded no failures.

A nonzero exit code is a normal child-process result, not a library failure.
Check `was_launched` and `has_exit_code` when the distinction matters.

## 4. Bound the execution

Add an overall deadline before starting the command:

```eiffel
command.set_timeout_milliseconds (5_000)
command.run
if command.execution_result.was_timed_out then
    io.error.put_string ("git did not finish within five seconds%N")
end
```

The deadline includes process execution and completion of captured streams.
On expiration, `os` terminates the managed process tree. Use `clear_timeout`
before a later run when no limit is required.

An `OS_COMMAND` retains its configuration and can be run again after
`can_start` becomes true. Executions on the same command cannot overlap.

## 5. Configure the child

Configuration changes apply to subsequent executions:

```eiffel
command.set_working_directory ("/path/to/repository")
command.set_environment_variable ("CI", "true")
command.unset_environment_variable ("GIT_DIR")
command.prepend_to_path ("/path/to/toolchain/bin")
command.set_input ("input bytes%N")
```

The command owns a copied environment snapshot. These calls do not change the
current Eiffel application's environment.

Standard output and error are captured and standard input is an empty pipe by
default. Stream destinations can be changed before starting:

```eiffel
command.inherit_stdin
command.inherit_stdout
command.discard_stderr
```

Use `capture_stdout` or `capture_stderr` to restore capture. `set_input`
restores piped stdin. `merge_stderr` redirects stderr to the selected stdout
destination.

## 6. Work with paths

`OS_FILE_PATH` is a path value with portable file-system operations:

```eiffel
local
    directory: OS_FILE_PATH
    file: OS_FILE_PATH
do
    create directory.make ("build/quick-start")
    directory.create_directory

    file := directory / "message.txt"
    file.write_text ("Hello from os%N")
    io.put_string_32 (file.text)
end
```

`create_directory` creates missing parents. `write_text` writes strict UTF-8
without a byte-order mark, while `text` decodes strict UTF-8. Use `bytes` and
`write_bytes` for non-text data, or the explicit encoding features for another
character set.

Before calling an operation, use status queries such as `exists`,
`is_directory`, `is_plain_file`, and `is_symbolic_link`. Eiffel contracts make
invalid combinations visible during development.

## 7. Run the repository example

The complete quick-start program and its standalone ECF file live in
[`examples/quick_start`](../examples/quick_start). From the `os` repository:

```console
make gobo
make ise
```

Each command builds the native archives, compiles the same example with the
selected compiler, and runs it. The program prints the installed Git version
and writes `build/quick-start/message.txt`.

Continue with the [reference guide](reference.md) for asynchronous execution,
streaming callbacks, executable lookup, termination guarantees, path traversal,
and replacement semantics.
