# Lightpanda Windows x64 社区移植版

这是 [Lightpanda](https://github.com/lightpanda-io/browser) 的原生 Windows x64 移植版。使用 Zig 构建，沿用上游 CLI、CDP 与 MCP 接口。

## 运行

从 [Windows x64 发布页](https://github.com/YZ-SI/lightpanda-windows-x64/releases/tag/1.0.5-windows.3) 下载 `lightpanda-1.0.5-windows-x64-3.zip`，用同页的 `SHA256SUMS.txt` 核对下载文件。完整解压后，在解压目录运行以下命令，并将随附的 Visual C++ 运行库与 `lightpanda.exe` 放在同一目录。

```powershell
.\lightpanda.exe version
.\lightpanda.exe fetch --dump html https://demo-browser.lightpanda.io/campfire-commerce/
.\lightpanda.exe serve --host 127.0.0.1 --port 9222
```

Puppeteer 和 Playwright 可通过 CDP 连接 `http://127.0.0.1:9222`。MCP stdio 可通过 `.\lightpanda.exe mcp` 启动。

- `fetch --terminate-ms 5000` 给抓取设置 5 秒硬时限。到期时，Windows 定时器触发 V8 中断，可停止正在运行的 JavaScript，包括死循环。
- `serve --unix-socket C:\Temp\lightpanda.sock` 可以在本地磁盘上创建套接字。请使用绝对路径，并确保父目录已存在。客户端需要支持 Winsock `AF_UNIX`。常规 Puppeteer 和 Playwright 连接可使用上面的 TCP 地址。

## 验证与维护

`1.0.5+windows.3` 来自[社区提交 `4c3c60af6`](https://github.com/YZ-SI/lightpanda-windows-x64/commit/4c3c60af6170834a7139ec9dd01a577040699978)，基于官方 [1.0.5](https://github.com/lightpanda-io/browser/releases/tag/1.0.5) 的提交 `8f220d5b49d9ceb3065f6d2c1bb10356dbc12b7f`。Windows 10 x64 上的上游 Web API、URL 和抓取子集合计通过 246 项，跳过 7 项。两端使用同一个夹具，验证内联脚本、静态和动态导入、IANA 时区及文档时间。统一换行符后，HTML 和 Markdown 输出与官方 Linux 版一致。

### 当前源码

Windows 10 x64 和 Linux x64 已执行同一组 2,445 个测试用例，两端均无失败。

| 平台 | 通过 | 跳过 |
| --- | ---: | ---: |
| 原生 Windows x64 | 2,429 | 16 |
| Linux x64 | 2,438 | 7 |

两端都跳过了 7 个需要启用 WPT 扩展的 WebDriver 用例。Windows 额外跳过 9 个涉及 Linux 崩溃信号、核心转储和 glibc 内存分配器调优的用例。

当前源码修复了 Windows 上的 WebDriver 数值解析、套接字发送回压和命令行帮助中的程序名显示。WebDriver 视口调整、MCP 文件下载、HTML 和 Markdown 输出也通过了与官方 Linux 1.0.5 的本地对照。干净 Windows 安装环境的复测待完成。

发布附件包含源码补丁、构建记录和 SHA-256 校验文件。也可以[从源码构建](README.md)，或查看[依赖锁定记录](upstream.json)和[上游同步、构建与验收流程](release/README.md)。

移植参考 qidiai 的原生 Windows 工作。项目沿用 [AGPL-3.0-only](../LICENSE)。 [浏览器 PR #3753](https://github.com/lightpanda-io/browser/pull/3753) · [V8 绑定 PR #219](https://github.com/lightpanda-io/zig-v8-fork/pull/219)
