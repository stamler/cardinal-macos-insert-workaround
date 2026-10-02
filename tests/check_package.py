#!/usr/bin/env python3
"""Packaging checks only: no native input, live installation, or new grants."""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


REPO = Path(__file__).resolve().parents[1]
ASSET = REPO / "karabiner/cardinal_insert.json"
BINARY = REPO / "build/cardinal-insert"


def run(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs)


def check_rule():
    data = json.loads(ASSET.read_text())
    assert len(data["rules"]) == 1
    manipulators = data["rules"][0]["manipulators"]
    assert len(manipulators) == 1
    rule = manipulators[0]
    assert rule["type"] == "basic"
    assert rule["from"]["key_code"] == "i"
    assert set(rule["from"]["modifiers"]["mandatory"]) == {"control", "option"}
    assert "to" not in rule, "Do not send another event before the release action."
    assert len(rule["to_after_key_up"]) == 1
    assert len(rule["conditions"]) == 1
    condition = rule["conditions"][0]
    assert condition["type"] == "frontmost_application_if"
    patterns = condition["bundle_identifiers"]
    assert len(patterns) == 1 and patterns[0].startswith("^") and patterns[0].endswith("$")
    pattern = re.compile(patterns[0])
    assert pattern.search("studio.kx.distrho.cardinal.native")
    for other in ("com.vcvrack.rack2", "studio.kx.distrho.cardinal.jack",
                  "studio.kx.distrho.cardinal.native.extra", "xstudio.kx.distrho.cardinal.native"):
        assert not pattern.search(other), other

    command = rule["to_after_key_up"][0]["shell_command"]
    run("/bin/sh", "-n", "-c", command)
    assert command.count("$HOME/") == 2

    # Exercise quoting with a mock helper, without repurposing the real HOME.
    with tempfile.TemporaryDirectory(prefix="cardinal package ' ") as tmp:
        root = Path(tmp)
        folder = root / ".config/karabiner/cardinal-insert-workaround"
        folder.mkdir(parents=True)
        mock = folder / "cardinal-insert"
        mock.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\"\n")
        mock.chmod(0o755)
        env = dict(os.environ, CARDINAL_TEST_HOME=str(root))
        run("/bin/sh", "-c", command.replace("$HOME", "${CARDINAL_TEST_HOME}"), env=env)
        assert (folder / "run.log").read_text() == "--karabiner\n"
    print("PASS: JSON scope, key-release action, shell syntax, and portable quoting")


def check_installer():
    installer = REPO / "scripts/install.sh"
    run("/bin/sh", "-n", str(installer))
    assert BINARY.is_file()
    with tempfile.TemporaryDirectory(prefix="cardinal staging ' ") as tmp:
        stage = Path(tmp)
        home = stage / Path(os.environ["HOME"]).relative_to("/")
        config_dir = home / ".config/karabiner"
        assets = config_dir / "assets/complex_modifications"
        folder = config_dir / "cardinal-insert-workaround"
        assets.mkdir(parents=True)
        config = config_dir / "karabiner.json"
        config.write_text('{"preserve_this_profile": true}\n')
        unrelated = assets / "unrelated.json"
        unrelated.write_text('{"preserve_this_asset": true}\n')
        config_before = config.read_bytes()
        unrelated_before = unrelated.read_bytes()
        env = dict(os.environ, CARDINAL_INSTALL_STAGING_ROOT=str(stage))
        run(str(installer), env=env)
        assert (folder / "cardinal-insert").read_bytes() == BINARY.read_bytes()
        assert (assets / ASSET.name).read_bytes() == ASSET.read_bytes()

        (folder / "cardinal-insert").write_bytes(b"previous helper fixture\n")
        (assets / ASSET.name).write_bytes(b"previous asset fixture\n")
        run(str(installer), env=env)
        backups = list((folder / "backups").iterdir())
        assert len(backups) == 1
        assert (backups[0] / "cardinal-insert").read_bytes() == b"previous helper fixture\n"
        assert (backups[0] / ASSET.name).read_bytes() == b"previous asset fixture\n"
        assert (folder / "cardinal-insert").read_bytes() == BINARY.read_bytes()
        assert (assets / ASSET.name).read_bytes() == ASSET.read_bytes()
        assert config.read_bytes() == config_before
        assert unrelated.read_bytes() == unrelated_before
    print("PASS: staged installation, backups, and preservation of unrelated configuration")


if __name__ == "__main__":
    check_rule()
    check_installer()
