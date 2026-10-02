# Karabiner-Elements setup

## 1. Build and install

Install Cardinal Native at `/Applications/CardinalNative.app`. Complete Karabiner-Elements' normal setup for your keyboard. This project was tested with Karabiner-Elements 16.3.0.

From the repository root:

```sh
make
make check
make install
```

The installer writes two files:

| File | Destination |
|---|---|
| Helper | `~/.config/karabiner/cardinal-insert-workaround/cardinal-insert` |
| Importable rule | `~/.config/karabiner/assets/complex_modifications/cardinal_insert.json` |

Existing copies are backed up below the helper folder's `backups/` directory, and the backup path is printed. Stop using the shortcut before updating; the installer refuses to replace a running `cardinal-insert` process. It does not edit `karabiner.json`, change profiles, enable rules, or grant permissions.

The source and documentation stay in your repository checkout. Retain it if you want to rebuild later. There is no `sudo` step.

## 2. Enable the Complex Modification

Open **Karabiner-Elements → Complex Modifications → Add predefined rule** (the button wording may differ by version). Find **Temporary Cardinal macOS Insert workaround** and enable:

> Cardinal Native only: Control+Option+I inserts a Tracker row (temporary Pugl workaround)

The complete import file is [`karabiner/cardinal_insert.json`](../karabiner/cardinal_insert.json). If you use a different import method, import that file; do not replace your entire Karabiner configuration with it.

Move this Cardinal-specific rule **above any generic Control+Option+I rule**. Karabiner uses the first matching manipulator. Keep your existing generic mapping if you want its behavior outside Cardinal. If this exact Cardinal-specific rule is already active from an earlier installation, keep that rule instead of enabling a duplicate.

The supplied condition matches only:

```json
"bundle_identifiers": ["^studio\\.kx\\.distrho\\.cardinal\\.native$"]
```

The helper also checks the executable path and frontmost PID. The rule does not match VCV Rack, Cardinal JACK, or DAW/plugin hosts.

## 3. Authorize Accessibility for the launcher

The shell-command launcher needs permission to send the helper's synthetic input:

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Enable **Karabiner-Console-User-Server**. If absent, use the **+** button and select:

   ```text
   /Library/Application Support/org.pqrs/Karabiner-Elements/Karabiner-Console-User-Server.app
   ```

3. Complete any Touch ID/password prompt yourself.

Accessibility is a broad system permission: grant it only if you trust Karabiner and this source code. This is the Console User Server, a separate component from Karabiner-Core-Service. Do not disable or replace Karabiner's other existing permissions.

The helper only performs permission preflight checks. It does not display a permission prompt, so silence is not evidence that access was granted. No additional permission is automatically requested by this project.

## 4. Test a disposable pattern

Open a throwaway Cardinal patch with Biset Tracker, select a populated row in a note column, and confirm arrow keys move the cursor. Press **Control+Option+I**, then release **I, Control, and Option**. Repeat with a CV column.

The Karabiner action runs when I is released. The helper waits until Control, Option, Command, and Shift are clear. Holding I does not generate repeated Insert actions. Holding modifiers while repeatedly tapping I can fill the four-request queue; release the whole chord between uses for predictable immediate feedback.

Each insertion shifts the selected column's later rows down and discards its last row. Inserting on the last row clears that row. Test on disposable data first.

## Logs and troubleshooting

```sh
tail -n 40 "$HOME/.config/karabiner/cardinal-insert-workaround/run.log"
```

| Log or symptom | What to check |
|---|---|
| No new `TRIGGER` | Rule enabled in the selected profile, above a generic rule; Cardinal Native frontmost; helper installed at the documented path. |
| `WORKER ... AX=0` or `post=0` | Console User Server's Accessibility grant. No event is posted in this case. |
| `SKIPPED wrong foreground` | Correct app variant, default `/Applications` location, and foreground focus. |
| `ACCEPT`, then `DROP ... expired` | Release all modifiers within two seconds. |
| `DROP ... focus_epoch` or `foreground` | Focus changed while the request was pending; the request is intentionally cancelled. |
| `REJECT ... full` / `stale_or_focus_or_full` | Queue limit, age, or foreground validation rejected the request. Slow down and release the complete chord. |
| Matching `DOWN request=N` and `UP request=N`, but no edit | Tracker must have a pattern and keyboard focus; select a row and test arrows. Logs show posting, not proof that Tracker consumed it. |
| A slow first press | Worker startup and AppKit initialization add latency. Warm results apply only before the worker's 400 ms idle exit. |

`WORKER_EXIT idle` confirms that the on-demand worker exited. Log timestamps are monotonic seconds, useful for durations rather than calendar dates. They include executable paths and process IDs; redact personal paths before sharing a log.

This command checks the process context that runs it, without sending input:

```sh
"$HOME/.config/karabiner/cardinal-insert-workaround/cardinal-insert" --check
```

A successful Terminal check does **not** establish permission for a Karabiner launch, and a failed Terminal check is not a reason to grant Terminal new permission. The real shortcut's `WORKER` entry is the relevant check.

For a custom Cardinal installation location, the helper's `TARGET_PATH` must be changed and rebuilt deliberately. The shipped rule/source support the default Native app only; broadening the app match is outside the tested setup.

## Rollback and removal

### Restore the previous helper

Stop using the shortcut and wait for the worker to exit. Use the backup directory printed by the installer:

```sh
workaround_dir="$HOME/.config/karabiner/cardinal-insert-workaround"
backup_dir="$workaround_dir/backups/REPLACE_WITH_PRINTED_BACKUP_NAME"
test -f "$backup_dir/cardinal-insert" || exit 1
if pgrep -x cardinal-insert >/dev/null; then
  echo 'Wait for the helper to exit before restoring it.' >&2
  exit 1
fi
cp -p "$backup_dir/cardinal-insert" "$workaround_dir/cardinal-insert.rollback"
mv -f "$workaround_dir/cardinal-insert.rollback" "$workaround_dir/cardinal-insert"
```

If you also need the previous import asset, restore `cardinal_insert.json` from that same backup to `~/.config/karabiner/assets/complex_modifications/`. Restoring an import asset does not edit an already-enabled rule. Leave unrelated rules and profiles alone. Rolling back to the older single-process helper also restores its slower timing and rapid-cancellation limitation.

### Remove after Cardinal includes the upstream fix

1. Disable only the Cardinal-specific rule and test ordinary Insert in a disposable pattern with the updated Cardinal.
2. Remove that specific rule from Complex Modifications. Keep any generic Insert mapping you still use.
3. Stop using the shortcut and wait for outstanding requests and the worker to finish. Archive any backups you want to retain.
4. Delete `~/.config/karabiner/assets/complex_modifications/cardinal_insert.json` and the dedicated `~/.config/karabiner/cardinal-insert-workaround/` folder. The repository checkout can also be removed if no longer needed.

Do not restore an entire old `karabiner.json`; that could discard unrelated newer edits. The Accessibility grant remains after uninstalling these files. If Console User Server no longer needs it for other rules, you can separately disable that specific Accessibility switch.

References: [shell commands and cancellation](https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/to/shell-command/), [key-release actions](https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/to-after-key-up/), [frontmost application conditions](https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/conditions/frontmost-application/).
