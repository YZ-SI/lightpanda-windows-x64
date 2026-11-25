import json
import os
import socket
import subprocess
import sys
import time
import urllib.request

exe = sys.argv[1]
env = dict(os.environ, LIGHTPANDA_DISABLE_TELEMETRY="true")
initialize = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "protocolVersion": "2025-06-18",
        "capabilities": {},
        "clientInfo": {"name": "windows-smoke", "version": "1"},
    },
}
tools = {"jsonrpc": "2.0", "id": 2, "method": "tools/list"}
initialized = {"jsonrpc": "2.0", "method": "notifications/initialized"}

def check_init(reply):
    assert reply["result"]["protocolVersion"] == "2025-06-18", reply

def check_tools(reply):
    assert any(tool["name"] == "goto" for tool in reply["result"]["tools"]), reply

data = "\n".join(map(json.dumps, [initialize, initialized, tools])) + "\n"
stdio = subprocess.run([exe, "mcp"], input=data, encoding="utf-8", stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, timeout=30, env=env, check=True)
replies = {row["id"]: row for row in map(json.loads, stdio.stdout.splitlines()) if "id" in row}
check_init(replies[1])
check_tools(replies[2])
print("PASS MCP stdio initialize and tools/list")

with socket.socket() as reserve:
    reserve.bind(("127.0.0.1", 0))
    port = reserve.getsockname()[1]

server = subprocess.Popen([exe, "mcp", "--host", "127.0.0.1", "--port", str(port)],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
try:
    for _ in range(80):
        if server.poll() is not None:
            raise RuntimeError("MCP HTTP server exited during startup")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                break
        except OSError:
            time.sleep(0.1)
    else:
        raise RuntimeError("MCP HTTP server did not start")

    def request(payload, session=None):
        headers = {"Content-Type": "application/json", "Accept": "application/json"}
        if session:
            headers["Mcp-Session-Id"] = session
        target = urllib.request.Request(f"http://127.0.0.1:{port}/mcp",
                                       json.dumps(payload).encode(), headers)
        with urllib.request.urlopen(target, timeout=10) as response:
            return response.headers.get("Mcp-Session-Id"), response.read()

    session, hello = request(initialize)
    assert session, hello
    check_init(json.loads(hello))
    request(initialized, session)
    _, available = request(tools, session)
    check_tools(json.loads(available))
    print("PASS MCP HTTP initialize, session, and tools/list")
finally:
    server.terminate()
    server.wait(timeout=10)
