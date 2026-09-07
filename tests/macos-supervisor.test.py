"""Exercise tunnel lifetime behavior without sudo, networking or a real EasyTier."""
import os
from pathlib import Path
import subprocess
import sys
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/macos-easytier-supervisor.sh"


class SupervisorTest(unittest.TestCase):
    def start(self, *args):
        process = subprocess.Popen(
            ["/bin/bash", str(SCRIPT), *args],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True,
        )
        self.addCleanup(self.close, process)
        return process

    @staticmethod
    def close(process):
        if process.stdin and not process.stdin.closed:
            process.stdin.close()
        try:
            process.wait(timeout=8)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdout.close()
            process.stderr.close()

    def test_gui_pipe_eof_stops_only_its_own_child(self):
        unrelated = subprocess.Popen(["/bin/sleep", "30"])
        self.addCleanup(unrelated.wait)
        self.addCleanup(unrelated.terminate)
        process = self.start(sys.executable, "-u", "-c",
                             "import os,time; print(os.getpid()); time.sleep(30)")
        pid = int(process.stdout.readline())
        os.kill(pid, 0)
        process.stdin.close()  # Also models a GUI crash: its pipe is closed by the OS.
        self.assertEqual(process.wait(timeout=8), 0)
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)
        self.assertIsNone(unrelated.poll())

    def test_child_failure_exit_status_reaches_the_gui(self):
        process = self.start(sys.executable, "-c", "raise SystemExit(23)")
        self.assertEqual(process.wait(timeout=5), 23)

    def test_paths_and_arguments_are_not_interpreted_as_shell_source(self):
        argument = "space ' quote $(exit 19) `exit 20` ; &"
        process = self.start(sys.executable, "-c", "import sys; print(sys.argv[1])", argument)
        self.assertEqual(process.stdout.readline().rstrip("\n"), argument)
        self.assertEqual(process.wait(timeout=5), 0)


if __name__ == "__main__":
    unittest.main()
