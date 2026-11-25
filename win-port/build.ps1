[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $V8Archive,

    [string] $Zig = 'zig',
    [string] $Version,
    [string] $TestFilter,
    [string] $RustArchive,
    [switch] $Snapshot
)

$ErrorActionPreference = 'Stop'
$zigExe = (Get-Command $Zig -CommandType Application -ErrorAction Stop).Source
$v8Path = (Resolve-Path -LiteralPath $V8Archive).Path
$rustPath = if ($RustArchive) { (Resolve-Path -LiteralPath $RustArchive).Path }
$root = Split-Path -Parent $PSScriptRoot
$common = @(
    '-Dtarget=x86_64-windows-gnu'
    '-Dcpu=x86_64'
    $(if ($TestFilter) { "-Doptimize=debug" } else { "-Doptimize=fast" })
    "-Dprebuilt_v8_path=$v8Path"
)
if ($Version) {
    $common += "-Dversion=$Version"
}
if ($rustPath) {
    $common += "-Dprebuilt_rust_path=$rustPath"
}

$importLibs = $env:LP_FILTERED_LIBS
if (-not $importLibs) {
    $importLibs = & (Join-Path $PSScriptRoot 'prepare-msvc.ps1')
}
$importLibs = (Resolve-Path -LiteralPath $importLibs).Path
$common += "-Dwindows_import_lib_path=$importLibs"

Push-Location -LiteralPath $root
try {
    if ($TestFilter) {
        & $zigExe build test @common "-Dtest-compile-filter=$TestFilter" --summary all
        if ($LASTEXITCODE -ne 0) { throw "Windows tests failed (Zig exit $LASTEXITCODE)." }
    } else {
        if ($Snapshot) {
            $snapshotPath = Join-Path $root '.lp-cache/windows-x64-snapshot.bin'
            New-Item -ItemType Directory -Path (Split-Path -Parent $snapshotPath) -Force | Out-Null
            & $zigExe build snapshot_creator @common -- $snapshotPath
            if ($LASTEXITCODE -ne 0) { throw "Windows snapshot creation failed (Zig exit $LASTEXITCODE)." }
            $common += "-Dsnapshot_path=$snapshotPath"
        }
        & $zigExe build @common --summary failures
        if ($LASTEXITCODE -ne 0) { throw "Windows build failed (Zig exit $LASTEXITCODE)." }
    }
} finally {
    Pop-Location
}
