[CmdletBinding()]
param([string] $MsvcLibX64 = $env:LP_MSVC_LIB_X64)

$ErrorActionPreference = 'Stop'
if (-not $MsvcLibX64) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $vs = & $vswhere -latest -products '*' -version '[17.0,18.0)' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or -not $vs) { throw 'Visual Studio 2022 C++ Build Tools were not found.' }

    $toolset = Get-ChildItem -Directory -LiteralPath (Join-Path $vs 'VC/Tools/MSVC') |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'lib/x64/msvcrt.lib') } |
        Sort-Object { [version] $_.Name } -Descending |
        Select-Object -First 1
    if (-not $toolset) { throw 'The Visual Studio x64 msvcrt import library was not found.' }
    $MsvcLibX64 = Join-Path $toolset.FullName 'lib/x64'
}

$source = (Resolve-Path -LiteralPath (Join-Path $MsvcLibX64 'msvcrt.lib')).Path
$toolsetRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $source))
$libExe = (Resolve-Path -LiteralPath (Join-Path $toolsetRoot 'bin/Hostx64/x64/lib.exe')).Path
$sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
$root = Split-Path -Parent $PSScriptRoot
$libraryDir = Join-Path $root ".lp-cache/msvc-gnu-interop-v1/$sourceHash"
$library = Join-Path $libraryDir 'msvcrt.lib'

if (-not (Test-Path -LiteralPath $library)) {
    $members = @(& $libExe /NOLOGO /LIST $source)
    if ($LASTEXITCODE -ne 0) { throw 'Could not read the MSVC archive.' }
    # Exclude the MSVC process startup objects. The final link uses Zig's GNU
    # startup, including its own TLS initialization and guard support.
    $startupMembers = @(
        'guard_xfg_dispatch.obj', 'cfgcheckthunk.obj', 'dispatchcfg.obj', 'pdblkup.obj',
        'initsect.obj', 'error.obj', 'checkcfg.obj', 'dyn_tls_init.obj',
        'loadcfg.obj', 'guard_support.obj', 'utility.obj', 'tlsdyn.obj', 'tlsdtor.obj',
        'exe_wwinmain.obj', 'exe_wmain.obj', 'exe_winmain.obj', 'exe_main.obj',
        'dll_dllmain.obj', 'ehvecdtr.obj', 'ehveccvb.obj', 'ehvecctr.obj',
        'ehvcccvb.obj', 'ehvccctr.obj'
    )
    $conflicts = @($members | Where-Object { (Split-Path -Leaf $_) -in $startupMembers })
    if ($conflicts.Count -ne $startupMembers.Count) {
        throw 'The MSVC startup members differ from the Windows GNU interop list.'
    }
    $removeArgs = @($conflicts | ForEach-Object { "/REMOVE:$_" })

    New-Item -ItemType Directory -Path $libraryDir -Force | Out-Null
    $temporary = Join-Path $libraryDir "$([guid]::NewGuid()).lib"
    try {
        $result = & $libExe /NOLOGO /MACHINE:X64 "/OUT:$temporary" @removeArgs $source
        if ($LASTEXITCODE -ne 0) { throw ($result -join "`n") }
        $remaining = @(& $libExe /NOLOGO /LIST $temporary)
        if ($LASTEXITCODE -ne 0 -or $remaining.Count -ne $members.Count - $conflicts.Count -or @($remaining | Where-Object { $_ -in $conflicts }).Count -ne 0) {
            throw 'The filtered archive did not remove exactly the MSVC startup members.'
        }
        try {
            [IO.File]::Move($temporary, $library)
        } catch [IO.IOException] {
            if (-not (Test-Path -LiteralPath $library)) { throw }
        }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    }
}
$libraryDir
