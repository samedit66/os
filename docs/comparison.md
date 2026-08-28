# Process API comparison

This document compares the `OS_COMMAND` process API with the process facilities
normally available from EiffelStudio and Gobo Eiffel. It is intended to explain
the library's useful differences, not to claim that it is a complete replacement
for every platform or compiler-specific API.

The comparison covers:

- EiffelStudio 25.12 `PROCESS` and `BASE_PROCESS`, as described in the
  [official process documentation](https://www.eiffel.org/doc/solutions/Process_and_BaseProcess);
- Gobo Eiffel 26.06 `EXECUTION_ENVIRONMENT.system`,
  `EXECUTION_ENVIRONMENT.launch`, and
  [`KL_SHELL_COMMAND`](https://github.com/gobo-eiffel/gobo/blob/master/library/kernel/src/misc/kl_shell_command.e);
- the current public contracts of [`OS_COMMAND`](../src/process/os_command.e)
  and [`OS_PROCESS_EXECUTION_RESULT`](../src/process/os_process_execution_result.e).

## Capability matrix

| Capability | `OS_COMMAND` | EiffelStudio `PROCESS` / `BASE_PROCESS` | Gobo execution facilities | Assessment |
| --- | --- | --- | --- | --- |
| Supported Eiffel compilers | The same public API works with EiffelStudio and Gobo Eiffel | Supplied as part of the EiffelStudio ecosystem | Available in Gobo, but without a full managed-process abstraction | Major `OS_COMMAND` advantage |
| Supported operating systems | Shared documented behavior on Linux, macOS, and Windows | Cross-platform, with several platform-specific controls and qualifications | Delegates much of its behavior to the runtime and platform shell | `OS_COMMAND` provides a narrower but explicit portability contract |
| Direct program execution | Executable and argument vector are separate; no shell quoting is required | `process_launcher` also accepts an executable and separate arguments | `system`, `launch`, and `KL_SHELL_COMMAND` accept a shell command string | Parity with EiffelStudio; major advantage over Gobo |
| Explicit shell execution | `make_shell` makes shell interpretation an explicit choice | A command-line launcher is available separately | Shell execution is the primary model | `OS_COMMAND` makes the safer mode the normal one |
| Synchronous and asynchronous execution | `run`, `start`, and `start_streaming` | `launch`, status queries, and wait operations | Synchronous `system` and fire-and-forget `launch` | Parity with EiffelStudio; more control than Gobo |
| Autonomous lifecycle progress | Supervision, pipe cleanup, and result publication continue without polling | Provides waiting and timer-based facilities; lifecycle management remains exposed to the client | Asynchronous launch returns no managed process object | `OS_COMMAND` has the most cohesive ownership model |
| Completed result value | One immutable result contains launch status, optional exit code, captured streams, termination state, timeout state, and failures | State is exposed through separate process attributes | Primarily a return or exit code | Major `OS_COMMAND` advantage |
| Output capture | Standard output and error are captured separately by default and retained in the result | Streams can be read or sent to agents, but there is no equivalent immutable aggregate result | No built-in output capture | `OS_COMMAND` is simpler for run-and-collect workflows |
| Streaming output | Separate stdout and stderr callbacks; ordering is preserved within each stream | Agent-based output and error redirection | No equivalent process-level callbacks | Broad parity with EiffelStudio; advantage over Gobo |
| Callback failure handling | Callback exceptions are contained, recorded as structured failures, and do not discard captured bytes | No equivalent structured failure result | Not applicable | `OS_COMMAND` has a stronger explicit contract |
| Output destinations | Capture, inherit, discard, and stderr-to-stdout merge | Parent stream, Eiffel stream/agent, file, and stderr merge | Requires shell redirection | EiffelStudio is broader because it supports files directly |
| Standard input | A copied byte snapshot followed by EOF, or inherited stdin | Incremental `put_string`, inherited input, and file input | Inherited input or shell facilities | EiffelStudio advantage for interactive processes |
| Working directory | A normalized absolute snapshot belongs to the command | Configurable per process | Usually requires changing global state or using shell syntax | Parity with EiffelStudio; advantage over Gobo |
| Child environment | Each command owns a copied environment with `set`, `unset`, `clear`, and `prepend_to_path` operations | A child environment table can be supplied | Environment mutation applies to the current process | `OS_COMMAND` offers the clearest isolated configuration model |
| Executable lookup | Uses the command's own `PATH` on every platform; the same environment is passed to the child | No separate portable resolver API | Delegated to the shell or runtime | Major reproducibility advantage for `OS_COMMAND` |
| Lookup without launching | `has_executable` and `executable_path` | No equivalent `PROCESS` query | No equivalent query | `OS_COMMAND` advantage |
| Execution deadline | An overall deadline covers the process and captured-pipe completion; expiration terminates the managed tree | `wait_for_exit_with_timeout` limits waiting but does not itself terminate the process | No managed timeout | Major `OS_COMMAND` advantage |
| Process-tree termination | Every execution is placed in a POSIX process group or Windows Job Object; `terminate` targets the managed tree | `terminate_tree` is available, subject to process-group configuration and platform qualifications | No managed process tree | `OS_COMMAND` provides the simpler default contract |
| Repeated termination | `terminate` is safe after completion and on repeated calls | Termination operations have stricter lifecycle preconditions | Not available | `OS_COMMAND` advantage for cleanup paths |
| Failure reporting | Portable failure categories, operation, description, and optional native error code | Status flags and lifecycle handlers | User/system exit-code distinction in `KL_SHELL_COMMAND` | Major `OS_COMMAND` advantage |
| Launch failure versus child exit | `was_launched` and `has_exit_code` distinguish a launch failure from a real exit such as code 127 | Can be inferred from separate status attributes | Shell execution can collapse the distinction into its status | `OS_COMMAND` makes the distinction explicit |
| Concurrent lifecycle calls | Command configuration, result publication, waiting, and termination are synchronized | `BASE_PROCESS` does not guarantee thread safety | Global environment and working-directory operations require client discipline | `OS_COMMAND` advantage |
| Process identifier | Not exposed | `id` is available | Not exposed by the shell helpers | EiffelStudio advantage |
| Lifecycle callbacks | Output callbacks only; no completion callback | Start, launch-success, launch-failure, exit, and termination handlers | None | EiffelStudio advantage |
| File-backed redirection | Not provided | Direct stdin, stdout, and stderr file redirection | Possible through shell syntax | EiffelStudio advantage |
| Windows console controls | No hidden, separate-console, or detached-console settings | Provides all three settings | Requires platform-specific shell techniques | EiffelStudio advantage |
| Terminal and PTY support | Synchronous inherited-terminal handoff on POSIX; no PTY | Explicit terminal-control settings on Unix; no portable PTY abstraction | No managed terminal API | EiffelStudio is more configurable |
| Detaching from a running child | Not supported; the command retains ownership until cleanup completes | `close` can release handles while allowing the process to continue | Asynchronous `launch` is effectively detached | `OS_COMMAND` is intentionally weaker for daemon workflows |
| Eiffel concurrency modes | Requires Eiffel thread support | `BASE_PROCESS` supports none, thread, and SCOOP; the extended `PROCESS` library requires threads | Basic shell execution does not require worker threads | `BASE_PROCESS` advantage |
| Installation | Requires building the supplied C11 native archive | Installed with EiffelStudio | Included with Gobo/FreeELKS | Built-in facilities are easier to adopt |
| API maturity | The public API is still being refined and may have breaking changes | Long-established library | Long-established basic facilities | Current `OS_COMMAND` disadvantage |
| Distribution license | No repository-level license file is currently supplied | Eiffel Forum License | MIT License | Current `os` adoption blocker |
| Comparative performance evidence | No comparative benchmark has been published | No current like-for-like benchmark against `OS_COMMAND` | No current like-for-like benchmark against `OS_COMMAND` | No performance advantage is claimed |

## Where `OS_COMMAND` is strongest

`OS_COMMAND` is most useful when an application needs one process API under
both EiffelStudio and Gobo Eiffel and wants a complete run-and-collect result.
Its main differentiators are the isolated environment snapshot, deterministic
executable lookup, autonomous cleanup, execution deadlines, default process-tree
ownership, and structured failure reporting.

Compared with Gobo's built-in facilities, it adds the missing managed-process
lifecycle. Compared with EiffelStudio `PROCESS`, it favors a smaller portable
surface with stronger default ownership and result semantics rather than the
largest possible set of redirection and platform controls.

## Known gaps

The most important capabilities available from EiffelStudio `PROCESS` but not
from `OS_COMMAND` are:

- incremental interactive standard input;
- direct file-backed redirection;
- access to the child process identifier;
- process lifecycle callbacks;
- Windows console configuration;
- releasing ownership of a still-running child.

PTYs, graceful signal protocols, and child-PID enumeration are also outside the
current scope. Applications that require these facilities should use a more
specialized platform or compiler-specific process library.
