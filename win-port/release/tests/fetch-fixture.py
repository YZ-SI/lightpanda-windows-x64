import functools
import http.server
import json
import os
import subprocess
import sys
import threading


FIXTURE = (b'<!doctype html><title>Lightpanda port fixture</title>'
           b'<h1>Native port test</h1><p id="value">before</p>'
           b'<script>document.querySelector("#value").textContent="script executed";</script>'
           b'<p id="modules">pending</p><p id="timezone">pending</p>'
           b'<script type="module" src="/main.js"></script>')

MODULES = {
    "/main.js": b'''
        import {message} from "/static.js";
        const {suffix} = await import("/dynamic.js");
        document.querySelector("#modules").textContent = message + suffix;
        const winter = new Date("2026-01-15T12:00:00Z").getTimezoneOffset();
        const summer = new Date("2026-07-15T12:00:00Z").getTimezoneOffset();
        document.querySelector("#timezone").textContent =
            [Intl.DateTimeFormat().resolvedOptions().timeZone, winter, summer, document.lastModified].join(", ");
    ''',
    "/static.js": b'export {message} from "/dependency.js";',
    "/dependency.js": b'export const message = "static and dynamic ";',
    "/dynamic.js": b'export const suffix = "modules executed";',
}

EXPECTED_TEXT = (
    "script executed",
    "static and dynamic modules executed",
    "America/New_York, 300, 240, 01/15/2026 07:00:00",
)


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        module = MODULES.get(self.path)
        if module is None and self.path != "/":
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/html" if module is None else "text/javascript")
        if module is None:
            self.send_header("Last-Modified", "Thu, 15 Jan 2026 12:00:00 GMT")
        self.end_headers()
        self.wfile.write(FIXTURE if module is None else module)

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
            dumps = {mode: run([executable, "fetch", "--dump", mode, "--timezone", "America/New_York", url])
                     for mode in ("html", "markdown")}
        finally:
            server.shutdown()
            thread.join()
    for mode, dump in dumps.items():
        text = dump.replace(r"\_", "_") if mode == "markdown" else dump
        missing = [expected for expected in EXPECTED_TEXT if expected not in text]
        if missing:
            raise RuntimeError(f"Unexpected {mode} output. Missing {missing!r}")
    print(json.dumps(dumps, ensure_ascii=True))
