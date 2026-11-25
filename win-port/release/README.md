# Update the Windows community build

Run the scripts from PowerShell 7. Use a short local NTFS path for the run directory. Each run records the official tag, commit, dependency inputs and the Windows source tree. The scripts create local candidates for manual approval.

## Prepare the official release

Export the patch from the last accepted source commit, then prepare a worktree from the latest official stable GitHub Release. Use `-Tag` to choose an official stable tag explicitly.

```powershell
$repo = (Resolve-Path .).Path
$flow = Join-Path $repo 'win-port/release'
$previousBase = '8f220d5b49d9ceb3065f6d2c1bb10356dbc12b7f'
$previousPort = 'cdddc1937a7f024c18891368d3425cea4354f86c'
$patch = Join-Path $env:TEMP 'lightpanda-windows-source.patch'
$runRoot = 'D:\lp-runs'

git -C $repo diff --binary --full-index "--output=$patch" $previousBase $previousPort
& "$flow\prepare-upstream.ps1" -Repository $repo -PreviousBase $previousBase `
    -PortPatch $patch -RunRoot $runRoot
```

Compare `upstream-build-inputs.diff` and the original source. Resolve Windows conflicts in the isolated worktree. If upstream adopted an equivalent Windows change, use the upstream implementation. Stage the reviewed port changes and confirm the browser tag and SHA in `win-port/upstream.json`. Record upstream issues with a minimal case and retest when upstream addresses them.

## Build and run upstream tests

Use the [build prerequisites](../README.md) and the new release's dependency pins. Check the official browser install workflow, the Zig V8 binding revision in `build.zig.zon`, and the matching V8 `DEPS` for Chromium tools. When those change, use fresh pinned V8 and tool directories. Enable process-local symlink access when required to unpack upstream dependencies.

```powershell
$run = Join-Path $runRoot $tag
& "$flow\build-candidate.ps1" -RunDirectory $run -V8Source $v8Source `
    -ZigV8Source $zigV8Source -DepotTools $depotTools -Gn $gnExe -Ninja $ninjaExe `
    -Zig $zigExe -EnableBuildSymlinks
```

Set `$tag` to the prepared official tag. Add `-SyncV8` when synchronizing a fresh V8 checkout. The build uses Cargo's locked dependency resolution, runs the upstream URL tests, then builds the native Windows executable. The output includes a source patch and dependency hashes.

## Verify the ZIP

Install Python and Node on Windows. Prepare the official [Lightpanda demo](https://github.com/lightpanda-io/demo) dependencies with `npm ci --ignore-scripts`. The 1.0.5 check used demo commit `dc2626bc413af87e1e87ea779caddbf31fe8aea5`. Use WSL with Python 3 and curl to run the checksum-verified official Linux binary for comparison. An attached Windows console is required for the Ctrl+Break test.

```powershell
& "$flow\verify-package.ps1" -RunDirectory $run -V8Source $v8Source `
    -DemoDirectory $demo -Dumpbin $dumpbinExe -MsvcRedist $msvcX64Runtime
```

The package step reconstructs the source tree from the official commit and verifies it against the build record. It checks the PE machine type and Microsoft runtime signatures, then runs smoke tests against the extracted ZIP, including the Windows fetch deadline. The candidate folder contains the ZIP, source patch, build record, SHA-256 sums and local acceptance result.

## Release review

Verify the ZIP on a clean Windows x64 environment. Review the version, supported behavior, test coverage and limits, corresponding source and dependencies, and checksums. Publish a GitHub Release after the maintainer approves the candidate. Use its accepted source commit and official base for the next update.

Set the same `-Revision` on the build and package commands when preparing a revised candidate for the same upstream tag.
