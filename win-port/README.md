# Windows x64 community build

This port starts from Lightpanda [1.0.5][release]. The exact source and dependency revisions are listed in [upstream.json](upstream.json). Lightpanda and its Windows changes use AGPL-3.0-only. The Windows V8 build adaptations draw on [browser PR #3753][browser-pr] and [zig-v8-fork PR #219][v8-pr].

## Build locally

1. Install Zig 0.17.1 x64, Rust with the `x86_64-pc-windows-gnu` target, Git, Python, and Visual Studio 2022 C++ Build Tools with Windows SDK 10.0.26100.0. Use a short NTFS path for the source and caches. Enable symlink creation for the build process so Zig can extract the unchanged upstream packages.
2. Check out the V8, zig-v8-fork, and depot_tools revisions in `upstream.json`. Pass `-Sync` on the first V8 build to fetch the pinned `DEPS` with depot_tools.
3. Obtain the Windows x64 GN and Ninja CIPD packages pinned in `upstream.json`. Build the V8 archive and then Lightpanda.

```powershell
.\win-port\build-v8.ps1 -V8Source $v8 -ZigV8Source $zigV8 -DepotTools $depot -Gn $gnExe -Ninja $ninjaExe -Jobs 12 -Sync
.\win-port\build.ps1 -V8Archive "$v8/out/lp-win-x64/obj/zig/c_v8.lib" -Version '1.0.5+windows.3'
```

The browser build writes `zig-out/bin/lightpanda.exe`. It generates a local import-library copy without the conflicting MSVC startup objects. The final executable uses the Windows GNU CRT startup. The installed SDK libraries remain intact. Add `-Snapshot` to generate and embed a snapshot from the same V8 archive. `-RustArchive` can reuse an independently built Windows GNU Rust static library. The GNU Windows link step filters a cached copy of the Rust archive so Zig supplies its own `f128` runtime functions. For direct Zig builds, pass the V8 archive with `-Dprebuilt_v8_path` and the path returned by `prepare-msvc.ps1` with `-Dwindows_import_lib_path`.

## Test and update

Run the full upstream suite in Debug mode with the Windows build script.

```powershell
.\win-port\build.ps1 -V8Archive "$v8/out/lp-win-x64/obj/zig/c_v8.lib" -Test
```

For a subset, use `-TestFilter 'WebApi:'` or `-TestFilter 'URL:'`. Omit `-Version` so that navigator assertions see the upstream development version. The Windows runner executes tests serially and starts a fresh process for each model-provider fixture that needs its own environment.

For each new stable release, resolve the official tag to a commit and compare it with the pin in `upstream.json`. Apply the Windows patch to that commit in a new worktree and review the diff. Refresh dependency and tool pins when the upstream release changes them. Compare the Windows executable against the matching official release using deterministic fixtures. Run the native executable in a clean Windows environment before submitting a package for manual release approval.

The Windows port currently supports x64. `fetch --terminate-ms 5000` sets a five-second hard deadline. At expiry a Win32 timer requests a V8 interrupt to stop running JavaScript, including infinite loops. `--timezone` applies an IANA zone to JavaScript and document timestamps. `serve --unix-socket C:\Temp\lightpanda.sock` requires an absolute path on a local drive, an existing parent directory, and a client that supports Winsock `AF_UNIX`. Most Windows CDP clients can connect over TCP. With the default CA configuration, a missing issuer in the browser's certificate store can be checked using the Windows system trust policy.

[release]: https://github.com/lightpanda-io/browser/releases/tag/1.0.5
[browser-pr]: https://github.com/lightpanda-io/browser/pull/3753
[v8-pr]: https://github.com/lightpanda-io/zig-v8-fork/pull/219
