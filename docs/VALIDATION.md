# Validation and reproduction

## What `make check` verifies

`make check` compiles the helper with warnings treated as errors, checks the JSON's shape and exact app scope, validates its shell syntax, and exercises its command with a harmless mock executable in a path containing spaces and an apostrophe. It tests installation and backup behavior under a temporary staging directory, without changing the user's HOME, live Karabiner configuration, or installed helper. The final `--check` call reports existing permissions and sends no input.

These are packaging checks. They do not grant Accessibility, enable a Karabiner rule, or edit a Tracker pattern. `AX=0` in this terminal context does not make the packaging checks fail; the physical Karabiner launch must be checked separately.

The build command is:

```sh
clang -fobjc-arc -Wall -Wextra -Werror \
  src/cardinal_insert.m \
  -framework Cocoa -framework ApplicationServices \
  -o build/cardinal-insert
```

Create `build/` first if running that command directly. `make` uses the local Apple toolchain and its default SDK/deployment target; it does not produce a universal or reproducible-byte-for-byte release binary.

## Native validation performed during development

Testing used macOS 26.6.2 on arm64, Apple clang 21.0.0, Karabiner-Elements 16.3.0, a separate native Pugl event-trace window, and the unmodified Cardinal Native 26.02 app with isolated disposable patterns.

- 36 rapid Insert requests produced matching worker down/up records and native Pugl press/release events.
- A diagnostic launcher was deliberately kept alive and killed with `SIGKILL` after the worker's down event. The worker delivered the corresponding native up event and exited normally.
- A 40-launch overlap stress run killed 34 launchers. All 23 accepted requests completed exactly once with matching native pairs. Requests killed before submission were not counted as accepted.
- Control, Option, Shift, and Command holds deferred insertion until release. A hold beyond the two-second request lifetime produced no Insert.
- A held-modifier burst accepted four requests and rejected six; after release, exactly four pairs were sent.
- Switching application focus away and back cancelled a waiting request. The wrong foreground app was rejected before submission.
- 27 candidate insertions and six further insertions using the deployed binary matched complete, freshly saved patch data. Tests covered both note columns, CV, repeated insertion, and final-row behavior. Unselected data remained unchanged.
- The reporter subsequently confirmed that the installed V2 physical Karabiner shortcut worked well. That confirmation is distinct from direct helper tests.

The historical raw traces and personal session files are not part of this repository. The checks below provide a practical regression procedure; instrumented native-event counting requires a separate trace host.

## Verify your installation

Use a disposable patch with Biset Tracker. Create a pattern with distinct values in two note columns and a CV column, including a populated last row. Save a baseline copy.

1. Select a middle row in the first note column. Confirm arrows work. Complete one Control+Option+I chord and release all modifiers. Verify the selected column shifts by one, the current row clears, and the previous last row is discarded.
2. Repeat with the second note column and the CV column. Verify values in the other columns remain unchanged.
3. Test the final row: only that row in the selected column should clear.
4. Complete several quick chords, releasing modifiers between them. Compare the number of accepted requests, matching `DOWN`/`UP` request IDs, and visible edits. Queue rejection is permitted at the documented limit; accepted, uncancelled requests should not duplicate.
5. Hold a modifier after releasing I, then release it within two seconds. The request should wait. Holding past two seconds should produce an expiry without an edit.
6. While a request waits on a held modifier, switch away from Cardinal and back. Release the modifier. The cancelled request should not insert later.
7. Check the original generic shortcut outside Cardinal. This repository's app-specific rule should not match.

Finally, save a new copy and compare the pattern with the expected row shifts. `DOWN`/`UP` logs alone demonstrate posting; they do not prove that Tracker received or applied the events.

## Reproducing cancellation tests

For a separate diagnostic build, compile with `TEST_HOLD_LAUNCHER` and a separate runtime suffix, retaining the production timing:

```sh
mkdir -p build
clang -fobjc-arc -Wall -Wextra -Werror \
  -DTEST_HOLD_LAUNCHER -DRUNTIME_SUFFIX='"cancellation-test"' \
  src/cardinal_insert.m \
  -framework Cocoa -framework ApplicationServices \
  -o build/cardinal-insert-test
```

This holds the launcher alive for 500 ms after acknowledgement. Run `--karabiner` only while the disposable Cardinal pattern is frontmost; invoking it from a frontmost Terminal correctly refuses to send input. A test harness can launch it after a short delay, read its `DOWN request=...` entry, and kill **the launcher PID**, never the worker or Cardinal. Confirm the same request gets `UP`, then `WORKER_EXIT idle`. The underlying native host's press/release trace is needed to verify receipt, rather than only posting.

Do not install the diagnostic binary as your normal helper or change production timing merely to make a test pass.

## Timing method and limits

The cold comparison used five launches per helper against the same native Pugl target, with more than 400 ms idle between requests. A monotonic timestamp was taken immediately before starting the launcher; the endpoint was native `NSEvent` key-down receipt. Median times were 142.806 ms for the previous helper and 106.319 ms for V2.

Eight warm V2 requests measured 11.432 ms median by the same method. The original component-only probe also measured approximately 1.5 ms from inside a warm launcher to posting, but that excludes startup and delivery and is not the headline comparison.

First execution after a rebuild sometimes took roughly 400 ms. These measurements exclude physical chord release, Karabiner dispatch, and drawing the changed pattern. They were collected on one machine; they do not imply ordinary hardware-key latency or guarantee identical timings elsewhere.
