# Lightpanda for Windows x64

Community port of the [Lightpanda headless browser](https://github.com/lightpanda-io/browser) for native Windows x64. The browser is built in Zig and exposes Lightpanda's CLI, Chrome DevTools Protocol (CDP) and MCP interfaces.

[简体中文](win-port/README.zh-CN.md) · [Build from source](win-port/README.md) · [Update and validate a build](win-port/release/README.md)

## Quick start

The first Windows ZIP is pending release approval. You can [build from source](win-port/README.md) now. Published ZIPs will appear under [Releases](https://github.com/YZ-SI/lightpanda-windows-x64/releases). Keep the included Visual C++ runtime DLLs next to the executable when using a ZIP.

```powershell
.\lightpanda.exe version
.\lightpanda.exe fetch --dump html https://demo-browser.lightpanda.io/campfire-commerce/
.\lightpanda.exe serve --host 127.0.0.1 --port 9222
```

Connect Puppeteer or Playwright over CDP at `http://127.0.0.1:9222`. Run `.\lightpanda.exe mcp` for the native MCP stdio transport.

## Verified build

| Item | Result |
| --- | --- |
| Community version | `1.0.5+windows.2` |
| Official base | [Lightpanda 1.0.5](https://github.com/lightpanda-io/browser/releases/tag/1.0.5) |
| Tested platform | Windows 10 x64 |
| Windows upstream subsets | 24 URL tests and 4 fetch tests |
| Linux upstream suite | 2,435 passed, 7 skipped on both the upstream and port source trees |
| Smoke tests | HTML and Markdown dumps, HTTPS, fetch hard deadline, Puppeteer and Playwright CDP, MCP stdio and HTTP, console shutdown |
| Linux comparison | HTML and Markdown output matched on a JavaScript fixture after line-ending normalization |

The `fetch --terminate-ms` hard deadline uses a native Windows timer and the existing V8 termination path. The full suite still has POSIX-only test fixtures. Windows Web API testing has a known module compatibility issue, and clean Windows host validation is pending.

The [tested source commit](https://github.com/YZ-SI/lightpanda-windows-x64/commit/cdddc1937a7f024c18891368d3425cea4354f86c) is based on upstream commit `8f220d5b49d9ceb3065f6d2c1bb10356dbc12b7f`. The [dependency record](win-port/upstream.json) identifies the corresponding V8 and toolchain versions.

## Attribution and license

The port reuses Lightpanda and credits qidiai's native Windows contributions in the browser and Zig V8 binding repositories. [Browser PR #3753](https://github.com/lightpanda-io/browser/pull/3753) · [V8 binding PR #219](https://github.com/lightpanda-io/zig-v8-fork/pull/219)

Lightpanda and the Windows port use [AGPL-3.0-only](LICENSE). See the [upstream README](https://github.com/lightpanda-io/browser/blob/1.0.5/README.md) for browser documentation.
