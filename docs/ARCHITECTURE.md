# Architecture and failure boundaries

## The two process roles

The same binary supports `--karabiner` (launcher), `--worker` (internal worker), and `--check` (permission preflight only).

The launcher verifies that the foreground application's bundle is `studio.kx.distrho.cardinal.native` and its executable is `/Applications/CardinalNative.app/Contents/MacOS/CardinalNative`. It sends one request containing the sender PID, target PID, protocol version, and monotonic creation time to a local Unix stream socket.

If no worker is available, the launcher starts one with `posix_spawn` in a separate process group. A nonblocking file lock permits a single worker for this user/runtime suffix. The socket lives in a mode-0700, user-owned directory under macOS's per-user temporary directory; the worker also checks the peer's user ID.

The worker acknowledges accepted requests. The launcher never resubmits a request after writing it: an uncertain acknowledgement must not become a duplicate edit. A launcher killed before submission may lose that shortcut. An acknowledgement means queued, not necessarily delivered: a later focus change or expiry can still cancel the request.

## Why a separate worker matters

Karabiner-Elements 16.3.0 replaces its previous shell-command process and uses `SIGKILL` during cleanup. `SIGKILL` cannot be blocked. Blocking only `SIGTERM`, `SIGINT`, and `SIGHUP` in a one-process helper does not protect a down/up pair.

Once the separate worker accepts a request, killing the launcher cannot kill that worker's key pair. The worker constructs native `NSEvent` events with both character fields set to `NSInsertFunctionKey`, copies their `CGEvent` representation, and posts to the verified PID. A raw Unicode override alone produced an incorrect key release during development.

A fallback release event is allocated before key-down. The normal release is constructed after the tested 12 ms gap; the fallback is available if that construction fails. Ordinary termination signals are blocked during the pair. If foreground focus changes after down, up still goes to the original target PID.

This is protection against **launcher replacement**, not a promise that the worker survives its own forced termination, an OS failure, or the target application exiting. Posting an event also cannot prove the target consumed it.

Sources: [Karabiner shell-command handler](https://github.com/pqrs-org/Karabiner-Elements/blob/v16.3.0/src/apps/ConsoleUserServer/include/console_user_server/shell_command_handler.hpp), [process cleanup using SIGKILL](https://github.com/pqrs-org/Karabiner-Elements/blob/v16.3.0/vendor/vendor/include/pqrs/process/process.hpp#L283-L285).

## Bounds and focus handling

| Setting | Value |
|---|---:|
| Pending queue capacity | 4 requests |
| Request lifetime | 2 seconds from launcher creation |
| Worker idle timeout | 400 ms |
| Key down/up gap | 12 ms |

The worker waits while Control, Option, Command, or Shift is held. It checks foreground state again before posting. App-activation notifications invalidate pending requests, including when the user switches away and back. These notifications concern application focus; the helper does not install a global keyboard listener.

After each pair the worker can accept more requests. It stays alive during an active burst, then exits once its queue has drained and it has been idle for 400 ms. This is an on-demand worker, not a login service. Socket backlog and pending requests are bounded; requests can be rejected or expire instead of accumulating indefinitely.

## Source provenance

The Objective-C file is the final V2 helper used for native tests and the reporter's physical verification. Packaging does not change its runtime logic. It uses the macOS SDK and system frameworks; this repository does not vendor Cardinal, Biset, Pugl, GLFW, or Karabiner source.

This workaround is separate from the one-line Pugl alias fix in [PR #145](https://github.com/lv2/pugl/pull/145). It should become unnecessary after that fix reaches the user's Cardinal build.
