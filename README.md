# Cardinal Insert workaround for macOS

**Use Control+Option+I to insert rows in Biset Tracker on Cardinal 26.02.**

This temporary workaround restores a specific missing Insert-key action without rebuilding Cardinal. It sends a native Insert press/release pair to the frontmost Cardinal Native window. The V2 helper has been physically verified by the original reporter.

## Quick start

You need macOS, [Cardinal](https://github.com/DISTRHO/Cardinal), [Karabiner-Elements](https://karabiner-elements.pqrs.org/), and Apple's Command Line Tools. If the developer tools are missing, install them with `xcode-select --install`. Python 3 is needed for the packaging checks.

```sh
git clone https://github.com/stamler/cardinal-macos-insert-workaround.git
cd cardinal-macos-insert-workaround
make
make check
make install
```

Then follow **[Karabiner setup](docs/KARABINER.md)** to enable the imported rule and configure Accessibility. `make install` copies the helper and rule asset; it does not edit your active Karabiner configuration or grant permissions.

In a disposable Tracker pattern, select a populated row, press **Control+Option+I**, and release all three keys. A blank row should appear in the selected column, moving later rows down and discarding the last row. Holding I does not autorepeat.

## Why Insert fails

On the affected Mac, AppKit delivers the physical Help/Insert key as `NSHelpFunctionKey` (`U+F746`, key code `0x72`). Cardinal's Pugl backend recognizes `NSInsertFunctionKey` but misses the Help alias, so Tracker never receives its expected Insert key.

```text
Affected path: Help U+F746 → Pugl raw character → Tracker key 63302 → no insertion
Workaround:    native Insert U+F727 → Pugl Insert → Tracker key 260 → insertion
```

VCV Rack uses GLFW, whose [macOS key table already maps `0x72` to Insert](https://github.com/VCVRack/glfw/blob/69f04b5504150a9dfed371d82c0fd75ab0f79464/src/cocoa_init.m#L260). Cardinal uses DPF/Pugl. The related [Biset issue #33](https://github.com/gibbonjoyeux/VCV-Biset/issues/33) describes VCV Rack Pro 2.5.1 on Sonoma; [GLFW also had that mapping then](https://github.com/VCVRack/glfw/blob/d46b57cdb16e521c8cf4290c9022278863a84022/src/cocoa_init.m#L260). This project addresses the reproduced Cardinal/Pugl bug, without claiming to explain the older VCV report.

The proper upstream fix is a one-line Pugl key alias:

- [Pugl PR #145](https://github.com/lv2/pugl/pull/145)
- [Cardinal issue #947](https://github.com/DISTRHO/Cardinal/issues/947)

Both remained open when this repository was prepared on October 2, 2026. Once your Cardinal release includes the fix, disable this workaround and test ordinary Insert before removing it. See [rollback and removal](docs/KARABINER.md#rollback-and-removal).

## How V2 handles rapid presses

```text
Karabiner → short launcher → on-demand worker → Insert down / up → Cardinal
```

Karabiner can forcibly terminate an earlier shell command when another starts. V2 lets the launcher submit one request to an independent worker, so terminating the launcher does not interrupt an accepted key pair.

The worker has a four-request pending limit, a two-second request lifetime, and a 400 ms idle timeout. It waits for modifiers to clear, cancels waiting requests when application focus changes, and never brings Cardinal forward. Its down/up gap is 12 ms. Excess or expired requests are discarded rather than delivered as an unbounded backlog. See [architecture and limits](docs/ARCHITECTURE.md).

## Tested scope and performance

| Item | Verified setup |
|---|---|
| System | macOS 26.6.2, Apple Silicon (`arm64`) |
| Host | Cardinal Native / Standalone 26.02 |
| App location | `/Applications/CardinalNative.app` |
| Keyboard mapper | Karabiner-Elements 16.3.0 |
| Compiler | Apple clang 21.0.0 |

Cardinal JACK, plug-in/DAW variants, Intel Macs, and other OS/tool versions have not been validated by this project. Source builds use the local compiler's native architecture.

Automated process-launch-to-native-key-down measurements on the same test target gave medians of **143 ms for the previous helper**, **106 ms for a cold V2 worker**, and **11 ms for warm V2 requests**. These exclude physical key-release time, Karabiner dispatch, and screen rendering. First execution after rebuilding was slower, around 400 ms. Warm results apply while the short-lived worker is still active.

Validation included 33 exact saved note/CV insertions, final-row behavior, modifier and focus checks, and forced launcher termination. In a 40-launch stress run, 34 launchers were killed and all 23 accepted requests produced matched native pairs. Physical V2 operation was subsequently confirmed by the reporter. These observations are not a guarantee for every Mac; [validation details](docs/VALIDATION.md) explain what was measured and how to check your installation.

## Security and permissions

Accessibility is a broad macOS permission that can let the authorized process control apps and send input. This workaround requires it for **Karabiner-Console-User-Server**, with the user's consent. The helper only checks existing permission; it never prompts for or changes permissions.

The code checks Cardinal's exact bundle identifier, executable path, and foreground PID. IPC stays in a user-owned private temporary directory. There is no network access, persistent service, launch agent, login item, or global input monitor in the helper. Logs contain timing, process identifiers, and executable paths; review/redact them before sharing. The installed Cardinal app and saved patches are not modified by installation.

## Repository

- [`src/cardinal_insert.m`](src/cardinal_insert.m): the user-tested V2 Objective-C source.
- [`Makefile`](Makefile): native macOS build, packaging checks, and installation.
- [`karabiner/cardinal_insert.json`](karabiner/cardinal_insert.json): importable Complex Modification.
- [`docs/KARABINER.md`](docs/KARABINER.md): setup, rule priority, permissions, troubleshooting, rollback, and removal.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): delivery protocol, cancellation, and failure boundaries.
- [`docs/VALIDATION.md`](docs/VALIDATION.md): tests, measurements, and reproduction steps.

No prebuilt binaries, personal Karabiner configuration, or music patches are distributed.

## License

[MIT](LICENSE), copyright 2026 Dean Stamler.
