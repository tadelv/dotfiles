"""Run with python3 -B -m unittest discover -s scripts -p 'test_review_candidate.py'."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

HELPER = Path(__file__).with_name("review_candidate.py")


class CandidateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.packets = []
        self.git("init", "-q")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Candidate test")
        self.git("config", "core.hooksPath", str(self.root / "no-hooks"))
        self.git("config", "commit.gpgsign", "false")
        (self.root / "tracked.txt").write_text("base\n")
        (self.root / "deleted.txt").write_text("delete me\n")
        self.git("add", ".")
        self.git("commit", "-qm", "base")
        self.base = self.git("rev-parse", "HEAD").decode().strip()

    def tearDown(self):
        for packet in self.packets:
            shutil.rmtree(packet)
        self.temp.cleanup()

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args])

    def helper(self, *args, ok=True, cwd=None):
        result = subprocess.run([sys.executable, str(HELPER), *map(str, args)], cwd=cwd or self.root,
                                capture_output=True, text=True)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        else:
            self.assertNotEqual(result.returncode, 0, result.stderr + result.stdout)
        return result

    def capture(self):
        packet = Path(json.loads(self.helper("capture", self.base).stdout)["packet"])
        self.packets.append(packet)
        return packet

    def test_staged_unstaged_new_deleted_and_committed_changes_are_in_one_packet(self):
        (self.root / "committed.txt").write_text("already committed\n")
        self.git("add", ".")
        self.git("commit", "-qm", "lane commit")
        (self.root / "tracked.txt").write_text("staged\n")
        self.git("add", "tracked.txt")
        (self.root / "tracked.txt").write_text("final unstaged\n")
        (self.root / "new name.txt").write_text("new test\n")
        (self.root / "deleted.txt").unlink()
        index = self.git("ls-files", "--stage", "-z")
        # The old lead command misses the actual working changes and the new test.
        old = self.git("diff", self.base + "...HEAD")
        self.assertNotIn(b"final unstaged", old)
        self.assertNotIn(b"new name.txt", old)
        packet = self.capture()
        patch = (packet / "diff.patch").read_bytes()
        for text in [b"final unstaged", b"new name.txt", b"deleted.txt", b"committed.txt"]:
            self.assertIn(text, patch)
        self.assertEqual((packet / "source/tracked.txt").read_text(), "final unstaged\n")
        self.assertFalse((packet / "source/deleted.txt").exists())
        self.assertEqual(self.git("ls-files", "--stage", "-z"), index)

    def test_edits_and_new_files_invalidate_but_do_not_change_frozen_source(self):
        packet = self.capture()
        (self.root / "tracked.txt").write_text("different\n")
        self.helper("check", packet, ok=False)
        self.assertEqual((packet / "source/tracked.txt").read_text(), "base\n")
        (self.root / "tracked.txt").write_text("base\n")
        (self.root / "new.txt").write_text("new\n")
        self.helper("check", packet, ok=False)

    def test_frozen_source_and_diff_cannot_drift_silently(self):
        packet = self.capture()
        frozen = packet / "source/tracked.txt"
        frozen.chmod(0o600)
        frozen.write_text("tampered\n")
        self.helper("check", packet, ok=False)
        frozen.write_text("base\n")
        (packet / "diff.patch").write_text("tampered patch\n")
        self.helper("check", packet, ok=False)

    def test_head_changes_invalidate_even_with_identical_files(self):
        packet = self.capture()
        self.git("commit", "--allow-empty", "-qm", "new head")
        self.helper("check", packet, ok=False)

    def test_final_commit_maps_only_the_reviewed_tree_and_parent(self):
        (self.root / "new.txt").write_text("review me\n")
        packet = self.capture()
        self.git("add", ".")
        self.git("commit", "-qm", "reviewed change")
        self.helper("check", packet, ok=False)
        self.helper("check", packet, "--committed")
        (self.root / "tracked.txt").write_text("post-commit edit\n")
        self.helper("check", packet, "--committed", ok=False)

    def test_partial_commit_cannot_reuse_candidate_approval(self):
        (self.root / "new.txt").write_text("not committed\n")
        (self.root / "tracked.txt").write_text("committed\n")
        packet = self.capture()
        self.git("add", "tracked.txt")
        self.git("commit", "-qm", "only part of candidate")
        self.helper("check", packet, "--committed", ok=False)

    def test_successful_gate_has_candidate_and_raw_log_receipt(self):
        packet = self.capture()
        self.helper("run", packet, "--", sys.executable, "-c", "print('exact evidence')")
        receipts = list(packet.glob("gate-*.json"))
        self.assertEqual(len(receipts), 1)
        receipt = json.loads(receipts[0].read_text())
        self.assertTrue(receipt["valid"])
        self.assertEqual(receipt["candidate"], json.loads((packet / "candidate.json").read_text())["id"])
        self.assertEqual(Path(receipt["log"]).read_text(), "exact evidence\n")
        self.assertEqual(receipt["exit_code"], 0)

    def test_receipt_log_tampering_and_mismatched_id_fail_closed(self):
        packet = self.capture()
        self.helper("run", os.path.relpath(packet, self.root), "--", sys.executable, "-c", "print('pass')")
        receipt_path = next(packet.glob("gate-*.json"))
        receipt = json.loads(receipt_path.read_text())
        log = Path(receipt["log"])
        log.write_text("different evidence\n")
        self.helper("check", packet, ok=False)
        log.write_text("pass\n")
        receipt["candidate"] = "another candidate"
        receipt_path.write_text(json.dumps(receipt))
        self.helper("check", packet, ok=False)

    def test_passing_gate_that_changes_code_is_invalid(self):
        packet = self.capture()
        self.helper("run", packet, "--", sys.executable, "-c",
                    "from pathlib import Path; Path('tracked.txt').write_text('changed')", ok=False)
        receipt = json.loads(next(packet.glob("gate-*.json")).read_text())
        self.assertFalse(receipt["valid"])
        self.assertEqual(receipt["exit_code"], 0)
        self.assertIn("Candidate changed", receipt["invalid_reason"])

    def test_failed_gate_and_missing_command_are_not_accepted(self):
        packet = self.capture()
        self.helper("run", packet, "--", sys.executable, "-c", "raise SystemExit(7)", ok=False)
        receipt = json.loads(next(packet.glob("gate-*.json")).read_text())
        self.assertEqual(receipt["exit_code"], 7)
        self.assertFalse(receipt["valid"])
        self.helper("run", packet, "--", "./nonexistent-gate", ok=False)

    def test_raw_bytes_modes_and_symlink_targets_are_bound(self):
        (self.root / "link").symlink_to("tracked.txt")
        packet = self.capture()
        self.assertFalse((packet / "source/link").is_symlink())
        self.assertEqual((packet / "source/link").read_text(), "tracked.txt")
        os.chmod(self.root / "tracked.txt", 0o755)
        self.helper("check", packet, ok=False)
        os.chmod(self.root / "tracked.txt", 0o644)
        (self.root / "tracked.txt").write_bytes(b"base\r\n")
        self.helper("check", packet, ok=False)

    def test_ignored_inputs_are_explicitly_outside_the_candidate(self):
        (self.root / ".gitignore").write_text("cache/\n")
        (self.root / "cache").mkdir()
        (self.root / "cache/output").write_text("before")
        packet = self.capture()
        self.assertFalse((packet / "source/cache").exists())
        (self.root / "cache/output").write_text("after")
        self.helper("check", packet)

    def test_dirty_submodules_fail_closed(self):
        self.git("update-index", "--add", "--cacheinfo", "160000," + self.base + ",sub")
        self.helper("capture", self.base, ok=False)

    def test_linked_worktree_and_unrelated_checkout(self):
        linked = self.root.parent / (self.root.name + "-linked")
        self.git("worktree", "add", "--detach", str(linked), "HEAD")
        try:
            result = self.helper("capture", self.base, cwd=linked)
            packet = Path(json.loads(result.stdout)["packet"])
            self.packets.append(packet)
            self.helper("check", packet, cwd=linked)
            self.helper("check", packet, ok=False)
        finally:
            self.git("worktree", "remove", str(linked))


if __name__ == "__main__":
    unittest.main()
