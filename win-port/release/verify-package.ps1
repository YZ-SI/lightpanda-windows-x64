#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $RunDirectory,
    [Parameter(Mandatory)] [string] $DemoDirectory,
    [Parameter(Mandatory)] [string] $Dumpbin,
    [Parameter(Mandatory)] [string] $MsvcRedist,
    [Parameter(Mandatory)] [string] $V8Source,
    [ValidateRange(1, 9999)] [int] $Revision = 1,
    [string] $OfficialLinuxWslPath,
    [string] $HttpsFixture = 'https://demo-browser.lightpanda.io/campfire-commerce/'
)

$ErrorActionPreference = 'Stop'
$run = (Resolve-Path -LiteralPath $RunDirectory).Path
$source = Join-Path $run 'src'
$candidate = Join-Path $run "candidate.windows.$Revision"
$receiptPath = Join-Path $run "build.windows.$Revision.json"
$build = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
$hex = '^[a-f0-9]{64}$'
$testDir = Join-Path $PSScriptRoot 'tests'
$version = $build.version
$packageName = "lightpanda-$($build.upstream.tag)-windows-x64-$Revision"
$output = Join-Path $run "release-candidate.windows.$Revision"
$acceptance = Join-Path $output 'acceptance.json'
if (Test-Path -LiteralPath $acceptance) { throw "This candidate has passed local verification. Its files are at $output." }

function Invoke-Checked([string] $File, [string[]] $ArgumentList) {
    & $File @ArgumentList
    if ($LASTEXITCODE -ne 0) { throw "$File failed with exit code $LASTEXITCODE." }
}
function Get-Sha256([string] $Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$originalExe = Join-Path $candidate 'lightpanda.exe'
$patch = Join-Path $candidate 'windows-source.patch'
$v8Archive = Join-Path $V8Source 'out/lp-win-x64/obj/zig/c_v8.lib'
if ((Get-Sha256 $originalExe) -cne $build.executableSha256 -or (Get-Sha256 $patch) -cne $build.sourcePatchSha256 -or
    (Get-Sha256 $v8Archive) -cne $build.v8Sha256) { throw 'An artifact differs from the build receipt.' }
$tree = Invoke-Checked git @('-C', $source, 'write-tree')
if ($tree -ne $build.sourceTree) { throw 'The worktree index differs from the built source tree.' }
Invoke-Checked git @('-C', $source, 'diff', '--quiet')

$originalIndex = $env:GIT_INDEX_FILE
$verificationIndex = Join-Path $run ('.verify-source-' + [Guid]::NewGuid().ToString('N') + '.index')
try {
    $env:GIT_INDEX_FILE = $verificationIndex
    Invoke-Checked git @('-C', $source, 'read-tree', $build.upstream.commit)
    Invoke-Checked git @('-C', $source, 'apply', '--cached', '--whitespace=error', $patch)
    if ((Invoke-Checked git @('-C', $source, 'write-tree')) -ne $build.sourceTree) {
        throw 'Applying the supplied patch to the official commit did not reproduce the build source tree.'
    }
} finally {
    $env:GIT_INDEX_FILE = $originalIndex
    if (Test-Path -LiteralPath $verificationIndex) { Remove-Item -LiteralPath $verificationIndex }
}

$asset = $build.upstream.officialLinuxX64
$digest = if ($asset) { $asset.digest -creplace '^sha256:', '' }
if ($digest -cnotmatch $hex -or $asset.url -cnotmatch '^https://github\.com/lightpanda-io/browser/releases/download/') {
    throw 'The official release metadata needs a Linux x64 binary with a published SHA-256.'
}
$wsl = (Get-Command wsl.exe -CommandType Application | Select-Object -First 1).Source
$linuxExe = $OfficialLinuxWslPath
if (-not $linuxExe) {
    $linuxDir = Invoke-Checked $wsl @('--exec', 'mktemp', '-d', '/tmp/lightpanda-port.XXXXXXXX')
    $linuxExe = "$linuxDir/lightpanda"
    Invoke-Checked $wsl @('--exec', 'curl', '--fail', '--location', '--silent', '--show-error',
                        '--retry', '2', '--max-time', '120', '--output', $linuxExe, $asset.url)
}
$linuxHash = ((Invoke-Checked $wsl @('--exec', 'sha256sum', '--', $linuxExe)) -split '\s+', 2)[0]
if ($linuxHash -cne $digest) { throw 'The Linux comparison binary differs from the official digest.' }
if (-not $OfficialLinuxWslPath) { Invoke-Checked $wsl @('--exec', 'chmod', '+x', '--', $linuxExe) }

$headers = Invoke-Checked $Dumpbin @('/HEADERS', $originalExe)
if (-not ($headers -match '8664 machine \(x64\)')) { throw 'Expected a Windows x64 PE executable.' }
$dependencies = Invoke-Checked $Dumpbin @('/DEPENDENTS', $originalExe)
$crtNames = @($dependencies | Select-String '^\s+(?<dll>(?:MSVCP|VCRUNTIME|CONCRT|VCCORLIB)\S+\.DLL)\s*$' |
    ForEach-Object { $_.Matches[0].Groups['dll'].Value.ToLowerInvariant() } | Sort-Object -Unique)
$staging = Join-Path $run ("staging.windows.$Revision-" + [Guid]::NewGuid().ToString('N'))
$payload = Join-Path $staging 'payload'
$unpack = Join-Path $staging 'unpack'
New-Item -ItemType Directory -Path $payload, $unpack, $output -Force | Out-Null
Copy-Item -LiteralPath $originalExe, (Join-Path $source 'LICENSE'), (Join-Path $source 'LICENSING.md'),
    (Join-Path $source 'win-port/upstream.json') -Destination $payload
foreach ($dll in $crtNames) {
    $path = Join-Path $MsvcRedist $dll
    $signature = Get-AuthenticodeSignature -LiteralPath $path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Microsoft Corporation(?:,|$)') {
        throw "Could not verify Microsoft's signature for $dll."
    }
    Copy-Item -LiteralPath $path -Destination $payload
}
$v8Licenses = Join-Path $payload 'licenses/v8'
$icuLicenses = Join-Path $payload 'licenses/icu'
New-Item -ItemType Directory -Path $v8Licenses, $icuLicenses -Force | Out-Null
Get-ChildItem -LiteralPath $V8Source -Filter 'LICENSE*' -File | Copy-Item -Destination $v8Licenses
Copy-Item -LiteralPath (Join-Path $V8Source 'third_party/icu/LICENSE') -Destination $icuLicenses
@"
# Lightpanda $version

Windows x64 community build from official release $($build.upstream.tag), commit $($build.upstream.commit).
Keep the supplied Microsoft runtime DLLs next to lightpanda.exe.

    .\lightpanda.exe version
    .\lightpanda.exe fetch --dump html https://example.com/
    .\lightpanda.exe serve --host 127.0.0.1 --port 9222

See LICENSE, LICENSING.md and upstream.json for the license and source pins.
"@ | Set-Content -LiteralPath (Join-Path $payload 'README.md') -Encoding utf8

$zip = Join-Path $staging "$packageName.zip"
Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $zip
Expand-Archive -LiteralPath $zip -DestinationPath $unpack
$exe = Join-Path $unpack 'lightpanda.exe'
if ((Get-Sha256 $exe) -ne $build.executableSha256) { throw 'The ZIP executable differs from the build receipt.' }

$log = Join-Path $run "logs.windows.$Revision/acceptance.log"
New-Item -ItemType Directory -Path (Split-Path -Parent $log) -Force | Out-Null
$fixture = Join-Path $testDir 'fetch-fixture.py'
$linuxFixture = (Invoke-Checked $wsl @('--exec', 'wslpath', '-a', ($fixture.Replace('\', '/')))).Trim()
$linuxVersion = $build.upstream.tag -creplace '^v', ''
$official = Invoke-Checked $wsl @('--exec', 'python3', $linuxFixture, $linuxExe, $linuxVersion) | ConvertFrom-Json
$oldTelemetry = $env:LIGHTPANDA_DISABLE_TELEMETRY
$oldAppData = $env:LOCALAPPDATA
$env:LIGHTPANDA_DISABLE_TELEMETRY = 'true'
$env:LOCALAPPDATA = Join-Path $staging '用户数据'
try {
    $windows = Invoke-Checked python @($fixture, $exe, $version) | ConvertFrom-Json
    ($windows | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $staging 'windows-fixture.json')
    ($official | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $staging 'official-fixture.json')
    if ($windows.html -cne $official.html -or $windows.markdown -cne $official.markdown) {
        throw "HTML or Markdown differs from the matching official Linux release. Both results are in $staging."
    }

    'PASS Windows output matches official Linux for HTML and Markdown' | Tee-Object -FilePath $log
    Invoke-Checked node @((Join-Path $testDir 'cdp.mjs'), $exe, $version, $DemoDirectory) |
        Tee-Object -FilePath $log -Append
    Invoke-Checked python @((Join-Path $testDir 'mcp.py'), $exe) | Tee-Object -FilePath $log -Append
    Invoke-Checked python @((Join-Path $testDir 'shutdown.py'), $exe) | Tee-Object -FilePath $log -Append
    $https = Invoke-Checked $exe @('fetch', '--dump', 'html', $HttpsFixture)
    if (-not ($https -match '<html')) { throw 'HTTPS fixture emitted no HTML.' }
    if (-not (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'lightpanda'))) { throw 'Expected a Unicode app data path.' }
    'PASS HTTPS and Unicode LOCALAPPDATA' | Tee-Object -FilePath $log -Append
} finally {
    $env:LIGHTPANDA_DISABLE_TELEMETRY = $oldTelemetry
    $env:LOCALAPPDATA = $oldAppData
}

Copy-Item -LiteralPath $zip, $patch, $receiptPath -Destination $output -Force
$checksums = @(
    "$(Get-Sha256 $zip)  $(Split-Path -Leaf $zip)"
    "$($build.sourcePatchSha256)  $(Split-Path -Leaf $patch)"
    "$(Get-Sha256 $receiptPath)  $(Split-Path -Leaf $receiptPath)"
)
$checksums | Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Encoding ascii
[ordered]@{
    version = $version
    status = 'local-verification-passed'
    cleanWindowsVerification = 'pending'
    publication = 'pending-manual-approval'
    localWindows = (Get-CimInstance Win32_OperatingSystem).Caption
    zipSha256 = Get-Sha256 $zip
    officialLinuxSha256 = $linuxHash
    dateUtc = [DateTime]::UtcNow.ToString('o')
} | ConvertTo-Json | Set-Content -LiteralPath $acceptance -Encoding utf8
Write-Host "Local candidate $version is ready at $output."
