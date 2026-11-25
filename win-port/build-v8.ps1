[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $V8Source,
    [Parameter(Mandatory)] [string] $ZigV8Source,
    [Parameter(Mandatory)] [string] $DepotTools,
    [Parameter(Mandatory)] [string] $Gn,
    [Parameter(Mandatory)] [string] $Ninja,
    [string] $Python = 'python',
    [string] $VisualStudio,
    [switch] $Sync,
    [ValidateRange(0, 128)] [int] $Jobs = 0
)

$ErrorActionPreference = 'Stop'
$pins = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'upstream.json') -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $V8Source).Path
$wrapper = (Resolve-Path -LiteralPath $ZigV8Source).Path
$depot = (Resolve-Path -LiteralPath $DepotTools).Path
$gnExe = (Resolve-Path -LiteralPath $Gn).Path
$ninjaExe = (Resolve-Path -LiteralPath $Ninja).Path
$pythonExe = (Get-Command $Python -CommandType Application -ErrorAction Stop).Source

foreach ($checkout in @(
    @{ Path = $source; Commit = $pins.v8.commit }
    @{ Path = $wrapper; Commit = $pins.zigV8.commit }
    @{ Path = $depot; Commit = $pins.depotTools.commit }
)) {
    $head = & git -C $checkout.Path rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $head -ne $checkout.Commit) {
        throw "Unexpected source revision at $($checkout.Path). Expected $($checkout.Commit)."
    }
}

& git -C $wrapper diff --quiet $pins.zigV8.commit -- src/binding.cpp src/inspector.h build-tools/.gn
if ($LASTEXITCODE -ne 0) { throw 'The official V8 binding sources or GN settings have local changes.' }

if (-not $VisualStudio) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $VisualStudio = & $vswhere -latest -products '*' -version '[17.0,18.0)' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or -not $VisualStudio) { throw 'Visual Studio 2022 C++ Build Tools were not found.' }
}

# Keep existing outputs up to date without forcing Ninja to recompile identical inputs.
function Write-BuildInput([string] $Path, [string] $Content) {
    if ((Test-Path -LiteralPath $Path) -and [IO.File]::ReadAllText($Path) -ceq $Content) { return }
    [IO.File]::WriteAllText($Path, $Content)
}

$env:PATH = "$depot;$env:PATH"
$env:DEPOT_TOOLS_UPDATE = '0'
$env:DEPOT_TOOLS_WIN_TOOLCHAIN = '0'
$env:GYP_MSVS_VERSION = '2022'
$env:vs2022_install = $VisualStudio
$env:GYP_MSVS_OVERRIDE_PATH = $VisualStudio

Push-Location -LiteralPath $source
try {
    if ($Sync) {
        $env:DEPOT_TOOLS_METRICS = '0'
        if (-not $env:GIT_CACHE_PATH) {
            $env:GIT_CACHE_PATH = Join-Path (Split-Path -Parent $source) 'git-cache'
        }
        $gitShim = Join-Path $depot 'git.bat'
        if (-not (Test-Path -LiteralPath $gitShim)) {
            $gitExe = (Get-Command git.exe -CommandType Application -ErrorAction Stop).Source
            Write-BuildInput $gitShim ('@echo off' + "`r`n" + '"' + $gitExe + '" -c core.autocrlf=false -c core.longpaths=true %*' + "`r`n")
        }
        $gclientConfig = @"
solutions = [
    {
        "name": ".",
        "url": "$($pins.v8.repository).git@$($pins.v8.commit)",
        "deps_file": "DEPS",
        "managed": False,
        "custom_deps": {},
    },
]
"@
        Write-BuildInput (Join-Path $source '.gclient') ($gclientConfig.Replace("`r`n", "`n") + "`n")
        & (Join-Path $depot 'gclient.bat') sync --no-history
        if ($LASTEXITCODE -ne 0) { throw 'V8 dependency synchronization failed.' }
    }
    if (-not (Test-Path -LiteralPath 'build/vs_toolchain.py')) {
        throw 'Sync the V8 DEPS with the pinned depot_tools using -Sync before building.'
    }
    New-Item -ItemType Directory -Path 'zig', 'out/lp-win-x64' -Force | Out-Null

    & $pythonExe (Join-Path $PSScriptRoot 'windows-v8-binding.py') (Join-Path $wrapper 'src/binding.cpp') (Join-Path $source 'binding.cpp')
    if ($LASTEXITCODE -ne 0) { throw 'The Windows V8 callback and time zone adaptation failed.' }

    foreach ($entry in @(
        @{ Source = 'src/inspector.h'; Destination = 'inspector.h' }
        @{ Source = 'build-tools/.gn'; Destination = 'zig/.gn' }
    )) {
        $inputFile = Join-Path $wrapper $entry.Source
        $outputFile = Join-Path $source $entry.Destination
        $inputHash = (Get-FileHash -LiteralPath $inputFile).Hash
        if (-not (Test-Path -LiteralPath $outputFile) -or (Get-FileHash -LiteralPath $outputFile).Hash -ne $inputHash) {
            Copy-Item -LiteralPath $inputFile -Destination $outputFile -Force
        }
    }
    $gnLines = & git -C $wrapper show "$($pins.zigV8.commit):build-tools/BUILD.gn"
    if ($LASTEXITCODE -ne 0) { throw 'Could not read the official V8 binding build file.' }
    $gnFile = ($gnLines -join "`n") + "`n"
    $normalFlag = '  cflags = [ "-fvisibility=default" ]'
    if (-not $gnFile.Contains($normalFlag)) { throw 'Review the upstream V8 binding flags for this revision.' }
    $windowsFlag = @"
  if (is_win) {
    cflags = [ "/clang:-fvisibility=default" ]
  } else {
    cflags = [ "-fvisibility=default" ]
  }
"@
    Write-BuildInput (Join-Path $source 'zig/BUILD.gn') ($gnFile.Replace($normalFlag, $windowsFlag.Replace("`r`n", "`n")))
    if (-not (Test-Path -LiteralPath 'build/config/gclient_args.gni')) {
        Write-BuildInput (Join-Path $source 'build/config/gclient_args.gni') "# Generated for the standalone V8 checkout`n"
    }

    & $pythonExe (Join-Path $PSScriptRoot 'windows-v8-compat.py') $source
    if ($LASTEXITCODE -ne 0) { throw 'The V8 Windows SDK and CRT adaptation failed.' }
    $gnArgs = @"
target_cpu = "x64"
use_siso = false
is_official_build = false
is_debug = false
symbol_level = 0
is_asan = false
is_tsan = false
v8_enable_sandbox = false
v8_monolithic = true
v8_monolithic_for_shared_library = true
v8_use_external_startup_data = false
is_component_build = false
use_allocator_shim = false
"@
    Write-BuildInput (Join-Path $source 'out/lp-win-x64/args.gn') ($gnArgs.Replace("`r`n", "`n") + "`n")
    & $gnExe --root=. --root-target=//zig --dotfile=zig/.gn "--script-executable=$($pythonExe.Replace('\','/'))" gen out/lp-win-x64
    if ($LASTEXITCODE -ne 0) { throw 'V8 GN generation failed.' }
    $ninjaArgs = @('-C', 'out/lp-win-x64', 'c_v8')
    if ($Jobs) { $ninjaArgs = @('-j', "$Jobs") + $ninjaArgs }
    & $ninjaExe @ninjaArgs
    if ($LASTEXITCODE -ne 0) { throw 'V8 compilation failed.' }
    Get-Item -LiteralPath 'out/lp-win-x64/obj/zig/c_v8.lib' | Select-Object -ExpandProperty FullName
} finally {
    Pop-Location
}
