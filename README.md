# Lightpanda for Windows x64

Community port of the [Lightpanda headless browser](https://github.com/lightpanda-io/browser) for native Windows x64. The browser is built in Zig and exposes Lightpanda's CLI, Chrome DevTools Protocol (CDP) and MCP interfaces.

[简体中文](win-port/README.zh-CN.md) · [Build from source](win-port/README.md) · [Update and validate a build](win-port/release/README.md)

## Quick start

Check [Releases](https://github.com/YZ-SI/lightpanda-windows-x64/releases) for an approved Windows ZIP. You can also [build it from source](win-port/README.md). Extract the ZIP and keep the included Visual C++ runtime DLLs alongside the executable.

```powershell
.\lightpanda.exe version
.\lightpanda.exe fetch --dump html https://demo-browser.lightpanda.io/campfire-commerce/
.\lightpanda.exe serve --host 127.0.0.1 --port 9222
```

Connect Puppeteer or Playwright over CDP at `http://127.0.0.1:9222`. Run `.\lightpanda.exe mcp` for the native MCP stdio transport.

## Verified build

| Item | Result |
| --- | --- |
| Community version | `1.0.5+windows.1` |
| Official base | [Lightpanda 1.0.5](https://github.com/lightpanda-io/browser/releases/tag/1.0.5) |
| Tested platform | Windows 10 x64 |
| Upstream tests | 24 URL tests passed |
| Smoke tests | HTML and Markdown dumps, HTTPS, Puppeteer and Playwright CDP, MCP stdio and HTTP, console shutdown |
| Linux comparison | HTML and Markdown output matched on a JavaScript fixture after line-ending normalization |

The full upstream test suite and a clean Windows host still need validation. The Windows build does not support the `fetch --terminate-ms` watchdog.

The [tested source commit](https://github.com/YZ-SI/lightpanda-windows-x64/commit/6da58fa89013f3ce15e86f4c9f85fde85f4cf8d7) is based directly on upstream commit `8f220d5b49d9ceb3065f6d2c1bb10356dbc12b7f`. The [dependency record](win-port/upstream.json) identifies the corresponding V8 and toolchain versions.

## Attribution and license

The port reuses Lightpanda and credits qidiai's native Windows contributions in the browser and Zig V8 binding repositories. [Browser PR #3753](https://github.com/lightpanda-io/browser/pull/3753) · [V8 binding PR #219](https://github.com/lightpanda-io/zig-v8-fork/pull/219)

Lightpanda and the Windows port use [AGPL-3.0-only](LICENSE). See the [upstream README](https://github.com/lightpanda-io/browser/blob/1.0.5/README.md) for browser documentation.
