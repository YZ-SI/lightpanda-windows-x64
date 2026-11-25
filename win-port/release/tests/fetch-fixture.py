import functools
import http.server
import json
import os
import subprocess
import sys
import threading


FIXTURE = (b'<!doctype html><title>Lightpanda port fixture</title>'
           b'<h1>Native port test</h1><p id="value">before</p>'
           b'<script>document.querySelector("#value").textContent="script executed";</script>')


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(FIXTURE)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    executable, expected_version = sys.argv[1:]
    run = functools.partial(subprocess.check_output, text=True, encoding="utf-8", timeout=30,
                            env=dict(os.environ, LIGHTPANDA_DISABLE_TELEMETRY="true"))
    actual_version = run([executable, "version"]).strip()
    if actual_version != expected_version:
        raise RuntimeError(f"Expected {expected_version}, received {actual_version}")
    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            url = f"http://127.0.0.1:{server.server_port}/"
            dumps = {mode: run([executable, "fetch", "--dump", mode, url])
                     for mode in ("html", "markdown")}
        finally:
            server.shutdown()
            thread.join()
    if any("script executed" not in dump for dump in dumps.values()):
        raise RuntimeError("The HTML or Markdown output omitted the JavaScript result.")
    print(json.dumps(dumps, ensure_ascii=True))
