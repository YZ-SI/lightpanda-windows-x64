# Lightpanda Windows x64 社区移植版

这是 [Lightpanda](https://github.com/lightpanda-io/browser) 的原生 Windows x64 移植版。使用 Zig 构建，沿用上游 CLI、CDP 与 MCP 接口。

## 运行

在 [Releases](https://github.com/YZ-SI/lightpanda-windows-x64/releases) 查看已批准发布的 Windows ZIP，也可[从源码构建](README.md)。解压后，将随附的 Visual C++ 运行库与 `lightpanda.exe` 放在同一目录。

```powershell
.\lightpanda.exe version
.\lightpanda.exe fetch --dump html https://demo-browser.lightpanda.io/campfire-commerce/
.\lightpanda.exe serve --host 127.0.0.1 --port 9222
```

Puppeteer 和 Playwright 可通过 CDP 连接 `http://127.0.0.1:9222`。MCP stdio 可通过 `.\lightpanda.exe mcp` 启动。

## 验证与维护

`1.0.5+windows.1` 基于官方 [1.0.5](https://github.com/lightpanda-io/browser/releases/tag/1.0.5) 的提交 `8f220d5b49d9ceb3065f6d2c1bb10356dbc12b7f`。Windows 10 x64 上通过了 24 项上游 URL 测试，以及抓取、CDP、MCP 和正常退出测试。对同一个 JavaScript 夹具，HTML 和 Markdown 输出在统一换行符后与官方 Linux 版一致。

Windows 全量测试与干净环境复测待完成，`fetch --terminate-ms` 暂不支持。查看[依赖锁定记录](upstream.json)和[上游同步、构建与验收流程](release/README.md)。

移植参考 qidiai 的原生 Windows 工作。项目沿用 [AGPL-3.0-only](../LICENSE)。 [浏览器 PR #3753](https://github.com/lightpanda-io/browser/pull/3753) · [V8 绑定 PR #219](https://github.com/lightpanda-io/zig-v8-fork/pull/219)
