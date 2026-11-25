# Lightpanda for Windows x64

Community port of the [Lightpanda headless browser](https://github.com/lightpanda-io/browser) for native Windows x64. The browser is built in Zig and exposes Lightpanda's CLI, Chrome DevTools Protocol (CDP) and MCP interfaces.

[简体中文](win-port/README.zh-CN.md) · [Build from source](win-port/README.md) · [Update and validate a build](win-port/release/README.md)

## Quick start

Download `lightpanda-1.0.5-windows-x64-3.zip` from the [Windows x64 release](https://github.com/YZ-SI/lightpanda-windows-x64/releases/tag/1.0.5-windows.3). Compare its hash with `SHA256SUMS.txt`, extract the whole archive, and run these commands from the extracted folder. Keep the included Visual C++ runtime DLLs next to `lightpanda.exe`.

```powershell
.\lightpanda.exe version
.\lightpanda.exe fetch --dump html https://demo-browser.lightpanda.io/campfire-commerce/
.\lightpanda.exe serve --host 127.0.0.1 --port 9222
```

Connect Puppeteer or Playwright over CDP at `http://127.0.0.1:9222`. Run `.\lightpanda.exe mcp` for the native MCP stdio transport.

## Verified build

| Item | Result |
| --- | --- |
| Community version | `1.0.5+windows.3` |
| Official base | [Lightpanda 1.0.5](https://github.com/lightpanda-io/browser/releases/tag/1.0.5) |
| Tested platform | Windows 10 x64 |
| Windows upstream test subsets | Web API 218 passed and 7 skipped, URL 24 passed, fetch 4 passed |
| Linux upstream suite | 2,435 passed, 7 skipped on both the upstream and port source trees |
| Smoke tests | HTTPS, fetch hard deadline, CDP over TCP and a local socket, MCP stdio and HTTP, duplicate listeners, console shutdown |
| Linux comparison | HTML and Markdown output matched for inline JavaScript, static and dynamic imports, and the IANA time zone fixture after line-ending normalization |

The Windows port uses the host's certificate trust policy and follows Winsock's local socket rules. The full upstream test suite stopped at compilation on native Windows with 29 diagnostics from test code, including POSIX `socketpair`, file permission assertions, and Windows UTF-16 argument handling. Clean Windows installation testing is pending.

The ZIP was built from [community commit `4c3c60af6`](https://github.com/YZ-SI/lightpanda-windows-x64/commit/4c3c60af6170834a7139ec9dd01a577040699978), based on upstream commit `8f220d5b49d9ceb3065f6d2c1bb10356dbc12b7f`. The Release includes the source patch, build record and SHA-256 checksums. The [dependency record](win-port/upstream.json) identifies the corresponding V8 and toolchain versions.

## Attribution and license

The port reuses Lightpanda and credits qidiai's native Windows contributions in the browser and Zig V8 binding repositories. [Browser PR #3753](https://github.com/lightpanda-io/browser/pull/3753) · [V8 binding PR #219](https://github.com/lightpanda-io/zig-v8-fork/pull/219)

Lightpanda and the Windows port use [AGPL-3.0-only](LICENSE). See the [upstream README](https://github.com/lightpanda-io/browser/blob/1.0.5/README.md) for browser documentation.
