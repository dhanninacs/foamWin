"""Run a program in its own console process group, send it Ctrl+Break after a delay, and wait.

    python send-ctrl-break.py <exe> <log> <seconds> [args...]

Exits with the program's exit code, or 1 if it is still running a minute after the signal
(it is then killed). Used by test-windows-fixes.ps1 for stopAtWriteNowSignal.
"""

import signal
import subprocess
import sys
import time


def main() -> int:
    exe, log, delay, *args = sys.argv[1:]
    with open(log, "wb") as out:
        process = subprocess.Popen(
            [exe, *args],
            stdout=out,
            stderr=subprocess.STDOUT,
            creationflags=subprocess.CREATE_NEW_PROCESS_GROUP,
        )
        time.sleep(float(delay))
        process.send_signal(signal.CTRL_BREAK_EVENT)
        try:
            return process.wait(timeout=60)
        except subprocess.TimeoutExpired:
            process.kill()
            return 1


if __name__ == "__main__":
    sys.exit(main())
