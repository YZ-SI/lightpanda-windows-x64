import os
import signal
import socket
import subprocess
import sys
import time
import urllib.request

with socket.socket() as reserve:
    reserve.bind(("127.0.0.1", 0))
    port = reserve.getsockname()[1]

env = dict(os.environ, LIGHTPANDA_DISABLE_TELEMETRY="true")
argv = [sys.argv[1], "serve", "--host", "127.0.0.1", "--port", str(port), "--log-level", "info"]
with subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env,
                      creationflags=subprocess.CREATE_NEW_PROCESS_GROUP) as browser:
    try:
        for attempt in range(60):
            if browser.poll() is not None:
                raise RuntimeError("browser closed before CDP became ready")
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{port}/json/version", timeout=1) as response:
                    assert response.status == 200
                break
            except OSError:
                time.sleep(0.15)
        else:
            raise RuntimeError("CDP did not become ready")
        browser.send_signal(signal.CTRL_BREAK_EVENT)
        output, errors = browser.communicate(timeout=12)
        assert browser.returncode == 0, (browser.returncode, errors.decode(errors="replace"))
        assert b"Received termination signal" in errors, errors.decode(errors="replace")
    finally:
        if browser.poll() is None:
            browser.kill()
            browser.wait()

with socket.socket() as check:
    check.bind(("127.0.0.1", port))

print("PASS Windows console interrupt, graceful exit, and port reuse")
