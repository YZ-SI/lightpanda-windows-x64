from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import subprocess
import sys
import threading
import time


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        script = (
            "while (true) {}"
            if self.path == "/loop"
            else 'document.querySelector("p").textContent = "script executed"'
        )
        body = f"<!doctype html><p>original</p><script>{script}</script>".encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


def main():
    exe = str(Path(sys.argv[1]).resolve())
    env = dict(os.environ, LIGHTPANDA_DISABLE_TELEMETRY="true")
    with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        def fetch(path, *args):
            url = f"http://127.0.0.1:{server.server_port}{path}"
            start = time.monotonic()
            result = subprocess.run(
                [exe, "fetch", "--log-level", "info", *args, url],
                capture_output=True, encoding="utf-8", errors="replace",
                timeout=8, env=env,
            )
            assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
            return result.stdout, result.stderr, time.monotonic() - start

        try:
            out, logs, elapsed = fetch("/loop", "--terminate-ms", "750")
            assert "executing script" in logs and "Deadline reached" in logs, (out, logs)
            assert 0.6 <= elapsed < 4, elapsed
            print(f"PASS 750 ms watchdog interrupts a running infinite JavaScript loop ({elapsed:.3f} s)")

            for _ in range(6):
                out, logs, elapsed = fetch("/loop", "--terminate-ms", "1")
                assert "Deadline reached" in logs and elapsed < 4, (out, logs, elapsed)
            print("PASS 1 ms deadline during browser startup (six runs)")

            for args in [(), ("--terminate-ms", "0"), ("--terminate-ms", "60000")]:
                out, logs, elapsed = fetch("/fast", "--dump", "html", *args)
                assert "script executed" in out and "Deadline reached" not in logs, (args, out, logs)
                assert elapsed < 4, (args, elapsed)
            print("PASS normal page with omitted, zero and pending 60-second deadlines")
        finally:
            server.shutdown()
            thread.join()


if __name__ == "__main__":
    main()
