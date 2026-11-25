# Windows x64 community build

This port starts from Lightpanda [1.0.5][release]. The exact source and dependency revisions are listed in [upstream.json](upstream.json). Lightpanda and its Windows changes use AGPL-3.0-only. The Windows V8 build adaptations draw on [browser PR #3753][browser-pr] and [zig-v8-fork PR #219][v8-pr].

## Build locally

1. Install Zig 0.17.1 x64, Rust with the `x86_64-pc-windows-gnu` target, Git, Python, and Visual Studio 2022 C++ Build Tools with Windows SDK 10.0.26100.0. Use a short NTFS path for the source and caches. Enable symlink creation for the build process so Zig can extract the unchanged upstream packages.
2. Check out the V8, zig-v8-fork, and depot_tools revisions in `upstream.json`. Pass `-Sync` on the first V8 build to fetch the pinned `DEPS` with depot_tools.
3. Obtain the Windows x64 GN and Ninja CIPD packages pinned in `upstream.json`. Build the V8 archive and then Lightpanda.

```powershell
.\win-port\build-v8.ps1 -V8Source $v8 -ZigV8Source $zigV8 -DepotTools $depot -Gn $gnExe -Ninja $ninjaExe -Jobs 12 -Sync
.\win-port\build.ps1 -V8Archive "$v8/out/lp-win-x64/obj/zig/c_v8.lib" -Version '1.0.5+windows.2'
```

The browser build writes `zig-out/bin/lightpanda.exe`. It generates a local import-library copy without the conflicting MSVC startup objects. The final executable uses the Windows GNU CRT startup. The installed SDK libraries remain intact. Add `-Snapshot` to generate and embed a snapshot from the same V8 archive. `-RustArchive` can reuse an independently built Windows GNU Rust static library. For direct Zig builds, pass the V8 archive with `-Dprebuilt_v8_path` and the path returned by `prepare-msvc.ps1` with `-Dwindows_import_lib_path`.

## Test and update

Run selected upstream tests through `build.ps1 -TestFilter 'URL:'`. The Windows test runner uses one process. Tests that directly use POSIX facilities such as `socketpair` or process-shared `mmap` require further Windows test-fixture work.

For each new stable release, resolve the official tag to a commit and compare it with the pin in `upstream.json`. Apply the Windows patch to that commit in a new worktree and review the diff. Refresh dependency and tool pins when the upstream release changes them. Compare the Windows executable against the matching official release using deterministic fixtures. Run the native executable in a clean Windows environment before submitting a package for manual release approval.

The Windows port currently supports x64. The native Windows `fetch --terminate-ms` watchdog uses a Win32 timer. The `serve --unix-socket` transport and `--timezone` overrides still have Windows compatibility gaps. Use a TCP listener for native Windows CDP and WebDriver clients. Keep a record of upstream behavior differences with the version and test context so that they can be checked again on the next upstream release.

[release]: https://github.com/lightpanda-io/browser/releases/tag/1.0.5
[browser-pr]: https://github.com/lightpanda-io/browser/pull/3753
[v8-pr]: https://github.com/lightpanda-io/zig-v8-fork/pull/219
