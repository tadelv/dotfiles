#!/usr/bin/env python3
"""Freeze A-Team review inputs and bind gate receipts to that checkout state."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import uuid


def git(root, *args, env=None):
    return subprocess.check_output(["git", "-C", str(root), *args], env=env)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return json.dumps(value, sort_keys=True).encode()


def save(path, value):
    path.write_bytes(encoded(value) + b"\n")


def files(root, snapshot=None):
    # shortcut: submodule contents need their own candidate; reject instead of claiming coverage.
    if any(row.startswith(b"160000 ") for row in git(root, "ls-files", "--stage", "-z").split(b"\0")):
        raise ValueError("Submodules require separate candidates; this helper does not cover them")
    names = set(git(root, "ls-files", "--cached", "--others", "--exclude-standard", "-z").split(b"\0"))
    result = []
    for name in sorted(names - {b""}):
        relative = Path(os.fsdecode(name))
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError("Unsafe candidate path")
        source = root / relative
        if any((root / parent).is_symlink() for parent in relative.parents):
            raise ValueError("Candidate path traverses a symlink: " + str(relative))
        if not source.exists() and not source.is_symlink():
            continue
        mode = source.lstat().st_mode
        if stat.S_ISLNK(mode):
            data = os.fsencode(os.readlink(source))
            kind = "symlink"
        elif stat.S_ISREG(mode):
            data = source.read_bytes()
            kind = "file"
        else:
            raise ValueError("Unsupported candidate file: " + str(relative))
        result.append({"path": str(relative), "mode": stat.S_IMODE(mode), "kind": kind, "sha256": digest(data)})
        if snapshot is not None:
            target = snapshot / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            # Symlinks are text for review, never followed into another checkout or host path.
            target.write_bytes(data)
            target.chmod(0o400)
    return result


def state(root, entries=None):
    return {"head": git(root, "rev-parse", "HEAD").decode().strip(),
            "files_sha256": digest(encoded(files(root) if entries is None else entries))}


def check(root, packet, committed=False):
    candidate = json.loads((packet / "candidate.json").read_bytes())
    identity = {key: value for key, value in candidate.items() if key != "id"}
    if digest(encoded(identity)) != candidate["id"]:
        raise ValueError("Candidate metadata changed")
    current = state(root)
    if committed:
        parents = git(root, "rev-list", "--parents", "-n", "1", "HEAD").decode().split()
        tree = git(root, "rev-parse", "HEAD^{tree}").decode().strip()
        if parents[1:] != [candidate["state"]["head"]] or tree != candidate["tree"]:
            raise ValueError("Final commit is not the reviewed tree on the captured parent")
        current["head"] = candidate["state"]["head"]
    if str(root) != candidate["repo"] or current != candidate["state"]:
        raise ValueError("Candidate changed: capture again, rerun gates, and obtain a new review")
    manifest = json.loads((packet / "files.json").read_bytes())
    if digest(encoded(manifest)) != candidate["state"]["files_sha256"]:
        raise ValueError("Candidate manifest changed")
    for entry in manifest:
        relative = Path(entry["path"])
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError("Unsafe snapshot path")
        source = packet / "source" / relative
        if (source.is_symlink() or any((packet / "source" / p).is_symlink() for p in relative.parents)
                or digest(source.read_bytes()) != entry["sha256"]):
            raise ValueError("Frozen review source changed: " + str(relative))
    if digest((packet / "diff.patch").read_bytes()) != candidate["diff_sha256"]:
        raise ValueError("Candidate diff changed")
    for path in packet.glob("gate-*.json"):
        receipt = json.loads(path.read_bytes())
        if receipt["candidate"] != candidate["id"]:
            raise ValueError("Gate receipt identifies another candidate")
        if receipt["valid"]:
            log = Path(receipt["log"])
            if (receipt["status"] != "finished" or receipt["exit_code"] != 0
                    or log.parent != packet.resolve() or log.is_symlink()
                    or digest(log.read_bytes()) != receipt["log_sha256"]):
                raise ValueError("Passing gate receipt/log changed")
    return candidate


def capture(root, base):
    base = git(root, "rev-parse", "--verify", base + "^{commit}").decode().strip()
    packet = Path(tempfile.mkdtemp(prefix="a-team-review-"))
    if packet.is_relative_to(root):
        raise ValueError("TMPDIR must be outside the checkout")
    entries = files(root, packet / "source")
    captured = state(root, entries)
    with tempfile.TemporaryDirectory(prefix="a-team-index-") as directory:
        env = {**os.environ, "GIT_INDEX_FILE": str(Path(directory) / "index")}
        git(root, "read-tree", "HEAD", env=env)
        git(root, "add", "--all", "--", ".", env=env)
        tree = git(root, "write-tree", env=env).decode().strip()
        patch = git(root, "diff", "--binary", "--no-ext-diff", "--no-textconv", base, tree, "--")
    candidate = {"repo": str(root), "base": base, "tree": tree, "state": captured,
                 "diff_sha256": digest(patch)}
    candidate["id"] = digest(encoded(candidate))
    save(packet / "candidate.json", candidate)
    save(packet / "files.json", entries)
    (packet / "diff.patch").write_bytes(patch)
    check(root, packet)
    print(json.dumps({"packet": str(packet), "candidate": candidate["id"], "tree": tree, "base": base}))


def run(root, packet, command):
    candidate = check(root, packet)
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        raise ValueError("A gate command is required after --")
    stem = "gate-" + uuid.uuid4().hex
    log = packet / (stem + ".log")
    receipt = packet / (stem + ".json")
    result = {"candidate": candidate["id"], "command": command, "log": str(log), "valid": False, "status": "running"}
    save(receipt, result)
    print(json.dumps({"receipt": str(receipt), "log": str(log)}), flush=True)
    with log.open("wb") as output:
        try:
            code = subprocess.run(command, cwd=root, stdout=output, stderr=subprocess.STDOUT).returncode
        except OSError as error:
            output.write(str(error).encode())
            code = 127
    result.update(status="finished", exit_code=code, log_sha256=digest(log.read_bytes()))
    try:
        check(root, packet)
        result["valid"] = code == 0
    except ValueError as error:
        result["invalid_reason"] = str(error)
    save(receipt, result)
    print(json.dumps(result))
    return 0 if result["valid"] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    commands.add_parser("capture").add_argument("base", help="Pinned lane base, not just HEAD's uncommitted diff")
    verify = commands.add_parser("check")
    verify.add_argument("packet", type=Path)
    verify.add_argument("--committed", action="store_true", help="Map a final local commit to the reviewed tree")
    gate = commands.add_parser("run")
    gate.add_argument("packet", type=Path)
    gate.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.action != "capture":
        args.packet = args.packet.resolve()
    root = Path(git(Path.cwd(), "rev-parse", "--show-toplevel").decode().strip()).resolve()
    if args.action == "capture":
        capture(root, args.base)
    elif args.action == "check":
        print(json.dumps({"candidate": check(root, args.packet, args.committed)["id"], "valid": True,
                          "head": git(root, "rev-parse", "HEAD").decode().strip()}))
    else:
        return run(root, args.packet, args.command)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print("Candidate error: " + str(error), file=sys.stderr)
        sys.exit(1)
