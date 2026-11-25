#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $RunDirectory,
    [Parameter(Mandatory)] [string] $V8Source,
    [Parameter(Mandatory)] [string] $ZigV8Source,
    [Parameter(Mandatory)] [string] $DepotTools,
    [Parameter(Mandatory)] [string] $Gn,
    [Parameter(Mandatory)] [string] $Ninja,
    [string] $Zig = 'zig',
    [string] $Python = 'python',
    [ValidateRange(1, 9999)] [int] $Revision = 1,
    [ValidateRange(1, 128)] [int] $V8Jobs = 12,
    [switch] $SyncV8,
    [switch] $EnableBuildSymlinks
)

$ErrorActionPreference = 'Stop'
$run = (Resolve-Path -LiteralPath $RunDirectory).Path
$source = Join-Path $run 'src'
$receipt = Join-Path $run "build.windows.$Revision.json"
if (Test-Path -LiteralPath $receipt) { throw "Build $Revision is already recorded. Use a new Revision for a revised candidate." }
$official = Get-Content -LiteralPath (Join-Path $run 'official-release.json') -Raw | ConvertFrom-Json
$pins = Get-Content -LiteralPath (Join-Path $source 'win-port/upstream.json') -Raw | ConvertFrom-Json
$version = "$($official.tag -creplace '^v', '')+windows"
$zigExe = (Get-Command $Zig -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$pythonExe = (Get-Command $Python -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$logs = Join-Path $run "logs.windows.$Revision"
New-Item -ItemType Directory -Path $logs -Force | Out-Null

function Invoke-Git {
    & git -C $source -c core.autocrlf=false @args
    if ($LASTEXITCODE -ne 0) { throw "git $($args[0]) failed with exit code $LASTEXITCODE. Inspect Windows port changes in $source." }
}
function Get-Sha256([string] $Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$base = Invoke-Git rev-parse HEAD
if ($base -ne $official.commit -or $base -ne $pins.browser.commit -or $official.tag -cne $pins.browser.tag) {
    throw 'The worktree HEAD, official release record, and Windows pins must match.'
}
Invoke-Git diff --quiet
$untracked = Invoke-Git ls-files --others --exclude-standard
if ($untracked) { throw 'Stage reviewed source files or move build scratch files outside the worktree.' }
Invoke-Git diff --cached --check
Invoke-Git diff --cached --quiet $base -- build.zig.zon src/rust/Cargo.lock LICENSE LICENSING.md
$tree = Invoke-Git write-tree
$zigVersion = & $zigExe version
if ($LASTEXITCODE -ne 0 -or $zigVersion -cne $pins.tools.zig) { throw "Use the reviewed Zig version $($pins.tools.zig)." }
$upstreamZon = Get-Content -LiteralPath (Join-Path $source 'build.zig.zon') -Raw
if (-not $upstreamZon.Contains("zig-v8-fork/archive/$($pins.zigV8.commit).tar.gz")) {
    throw 'Review the official Zig V8 binding pin in build.zig.zon and update win-port/upstream.json.'
}
$upstreamAction = Get-Content -LiteralPath (Join-Path $source '.github/actions/install/action.yml') -Raw
$upstreamV8 = [regex]::Match($upstreamAction, '(?m)^  v8:\s*\r?\n(?:(?: {4}[^\r\n]+)\r?\n)*? {4}default: [''"](?<tag>[^''"]+)[''"]')
if (-not $upstreamV8.Success -or $upstreamV8.Groups['tag'].Value -cne $pins.v8.tag) {
    throw 'Review the V8 version used by the upstream build and update the Windows pins and recipe.'
}
if ($EnableBuildSymlinks) { & (Join-Path $PSScriptRoot 'enable-build-symlinks.ps1') }

$oldPath = $env:PATH
$oldTelemetry = $env:LIGHTPANDA_DISABLE_TELEMETRY
$env:LIGHTPANDA_DISABLE_TELEMETRY = 'true'
try {
    $v8Args = @{
        V8Source = $V8Source
        ZigV8Source = $ZigV8Source
        DepotTools = $DepotTools
        Gn = $Gn
        Ninja = $Ninja
        Python = $pythonExe
        Jobs = $V8Jobs
        Sync = $SyncV8
    }
    & (Join-Path $source 'win-port/build-v8.ps1') @v8Args 2>&1 |
        Tee-Object -FilePath (Join-Path $logs 'v8.log') | Out-Host
    $v8Archive = (Resolve-Path -LiteralPath (Join-Path $V8Source 'out/lp-win-x64/obj/zig/c_v8.lib')).Path

    $rustTarget = 'x86_64-pc-windows-gnu'
    $cargoDir = Join-Path $run 'cargo'
    cargo build --locked --release --target $rustTarget --target-dir $cargoDir --manifest-path (Join-Path $source 'src/rust/Cargo.toml') 2>&1 |
        Tee-Object -FilePath (Join-Path $logs 'rust.log') | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'The upstream Rust static library did not build.' }
    $rustArchive = (Resolve-Path -LiteralPath (Join-Path $cargoDir "$rustTarget/release/liblightpanda_ffi.a")).Path

    $buildScript = Join-Path $source 'win-port/build.ps1'
    $buildArgs = @{ Zig = $zigExe; V8Archive = $v8Archive; RustArchive = $rustArchive }
    $testLog = Join-Path $logs 'upstream-windows-tests.log'
    $savedFilter = $env:TEST_FILTER
    try {
        $env:TEST_FILTER = $null
        & $buildScript @buildArgs -Test 2>&1 | Tee-Object -FilePath $testLog | Out-Host
    } finally {
        $env:TEST_FILTER = $savedFilter
    }
    if (-not (Select-String -LiteralPath $testLog -Pattern '\b([1-9]\d*) of \1 tests passed\b' -Quiet)) {
        throw 'The upstream Windows test log contains no complete nonzero test pass.'
    }
    & $buildScript @buildArgs -Version $version 2>&1 | Tee-Object -FilePath (Join-Path $logs 'windows-build.log') | Out-Host
} finally {
    $env:PATH = $oldPath
    $env:LIGHTPANDA_DISABLE_TELEMETRY = $oldTelemetry
}

Invoke-Git diff --quiet
if ((Invoke-Git write-tree) -ne $tree) { throw 'The reviewed source tree changed during the build.' }
$packageInputs = Join-Path $run "candidate.windows.$Revision"
New-Item -ItemType Directory -Path $packageInputs -Force | Out-Null
$exe = Join-Path $packageInputs 'lightpanda.exe'
Copy-Item -LiteralPath (Join-Path $source 'zig-out/bin/lightpanda.exe') -Destination $exe -Force
$reportedVersion = & $exe version
if ($LASTEXITCODE -ne 0 -or "$reportedVersion".Trim() -cne $version) { throw 'The executable reports an unexpected version.' }
$patch = Join-Path $packageInputs 'windows-source.patch'
Invoke-Git diff --cached --binary --full-index --no-ext-diff "--output=$patch" $base
[ordered]@{
    version = $version
    upstream = $official
    sourceTree = $tree
    sourcePatchSha256 = Get-Sha256 $patch
    executableSha256 = Get-Sha256 $exe
    v8Sha256 = Get-Sha256 $v8Archive
    rustSha256 = Get-Sha256 $rustArchive
    gnSha256 = Get-Sha256 $Gn
    ninjaSha256 = Get-Sha256 $Ninja
    zig = $zigVersion
    rust = (& rustc --version)
    pins = $pins
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $receipt -Encoding utf8
Write-Host "Built $version. Candidate inputs and the source patch are in $packageInputs."
