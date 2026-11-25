#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Repository,
    [Parameter(Mandatory)] [string] $PreviousBase,
    [Parameter(Mandatory)] [string] $PortPatch,
    [Parameter(Mandatory)] [string] $RunRoot,
    [string] $Tag,
    [switch] $ReplaySameRelease
)

$ErrorActionPreference = 'Stop'
$remote = 'https://github.com/lightpanda-io/browser.git'
$api = 'https://api.github.com/repos/lightpanda-io/browser/releases'
$repo = (Resolve-Path -LiteralPath $Repository).Path
$patch = (Resolve-Path -LiteralPath $PortPatch).Path

function Invoke-Git {
    & git -C $repo -c core.autocrlf=false -c core.longpaths=true @args
    if ($LASTEXITCODE -ne 0) { throw "git $($args[0]) failed with exit code $LASTEXITCODE." }
}

if ($Tag -and $Tag -cnotmatch '^v?\d+\.\d+\.\d+$') { throw 'Specify a stable release tag such as 1.0.5.' }
$releaseUri = if ($Tag) { "$api/tags/$Tag" } else { "$api/latest" }
$release = Invoke-RestMethod -Uri $releaseUri -TimeoutSec 30
if ($release.draft -or $release.prerelease -or $release.tag_name -cnotmatch '^v?\d+\.\d+\.\d+$' -or
    ($Tag -and $release.tag_name -cne $Tag)) { throw 'The requested official release is not stable.' }
$Tag = $release.tag_name
$ref = "refs/tags/$Tag"
$refs = @(Invoke-Git ls-remote --exit-code $remote $ref ("${ref}^{}"))
$peeled = $refs | Where-Object { $_.EndsWith('^{}') } | Select-Object -First 1
$pin = if ($peeled) { $peeled } elseif ($refs.Count -eq 1) { $refs[0] } else { throw 'Unable to resolve the official tag.' }
$commit = ($pin -split '\s+', 2)[0]
if ($commit -cnotmatch '^[a-f0-9]{40}$') { throw 'Invalid official commit.' }
$base = Invoke-Git rev-parse --verify --end-of-options "${PreviousBase}^{commit}"
if ($commit -eq $base -and -not $ReplaySameRelease) {
    Write-Host "Official stable tag $Tag already matches the last accepted source ($commit)."
    return
}

$run = Join-Path ([IO.Path]::GetFullPath($RunRoot)) $Tag
if (Test-Path -LiteralPath $run) { throw "This run already exists. Resume it at $run or select another RunRoot." }
New-Item -ItemType Directory -Path $run | Out-Null
$source = Join-Path $run 'src'
$linux = $release.assets | Where-Object name -CEQ 'lightpanda-x86_64-linux' | Select-Object -First 1
[ordered]@{
    tag = $Tag
    commit = $commit
    releaseUrl = $release.html_url
    previousBase = $base
    inputPatchSha256 = (Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant()
    officialLinuxX64 = if ($linux) { @{ url = $linux.browser_download_url; digest = $linux.digest } }
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $run 'official-release.json') -Encoding utf8

Invoke-Git fetch --no-tags $remote $commit
if ((Invoke-Git rev-parse --verify "${commit}^{commit}") -ne $commit) { throw 'The official commit did not resolve.' }
$deltaPath = Join-Path $run 'upstream-build-inputs.diff'
Invoke-Git diff "--output=$deltaPath" $base $commit -- build.zig build.zig.zon src/rust/Cargo.lock src/rust/Cargo.toml .github/actions/install .github/workflows/release.yml
Invoke-Git worktree add --detach $source $commit

& git -C $source -c core.autocrlf=false -c core.longpaths=true apply --3way --index $patch 2>&1 |
    Tee-Object -FilePath (Join-Path $run 'patch-apply.log')
if ($LASTEXITCODE -ne 0) {
    throw "Windows patch needs review in $source. The conflict state and logs are preserved."
}

$pinFile = Join-Path $source 'win-port/upstream.json'
$pins = Get-Content -LiteralPath $pinFile -Raw | ConvertFrom-Json
if ($pins.browser.tag -cne $Tag -or $pins.browser.commit -ne $commit) {
    $pins.browser.tag = $Tag
    $pins.browser.commit = $commit
    $pinsJson = ($pins | ConvertTo-Json -Depth 10).Replace("`r`n", "`n")
    [IO.File]::WriteAllText($pinFile, $pinsJson + "`n")
    & git -C $source -c core.autocrlf=false -c core.longpaths=true add -- win-port/upstream.json
    if ($LASTEXITCODE -ne 0) { throw 'Failed to stage the revised upstream pin.' }
}
Write-Host "Prepared $source at $commit. Review $deltaPath and the Windows patch before building."
