<#
.SYNOPSIS
    Publishes a Whisperly build: a release in this repository, then the manifest
    the website and the app read.

.DESCRIPTION
    Promote a build that CI already attached to a release in the source repository:

        ./Publish-Release.ps1 -Platform windows -FromTag windows-v0.6.3

    or publish a file you built yourself:

        ./Publish-Release.ps1 -Platform windows -File .\WhisperlySetup-v0.6.3.exe -Notes .\notes.md

    The order is deliberate. The release and its files go up first and are
    checked to download without a GitHub account; only then is the manifest
    committed. Every installed copy of Whisperly reads that manifest once a day,
    so it must never name a version nobody can download yet.

    Add -WhatIfOnly to run every check and print the result without publishing.
#>
#Requires -Version 7
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateSet('windows', 'mac')] [string] $Platform,
    # A release tag in the source repository, such as windows-v0.6.3 or v1.0.2.
    [string] $FromTag,
    # Or a local installer (.exe) or disk image (.dmg).
    [string] $File,
    # Taken from the tag or the file name when omitted.
    [string] $Version,
    # Release notes: text, or a path to a Markdown file. Defaults to the source release's notes.
    [string] $Notes,
    [string] $SourceRepo = 'mbn-code/whisperly',
    [switch] $WhatIfOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = 'mbn-code/whisperly-download'
$siteUrl = 'https://mbn-code.github.io/whisperly-download/'
$root = $PSScriptRoot

# Tags follow what the apps expect. The Mac updater reads this repository's
# releases and takes plain vX.Y.Z tags, skipping anything that starts with
# "windows-" and anything marked as a pre-release.
$spec = @{
    windows = @{ Pattern = 'WhisperlySetup*.exe'; Extra = 'Whisperly-win-x64.zip'; Manifest = 'windows-latest.json'; TagPrefix = 'windows-v'; Name = 'Windows' }
    mac     = @{ Pattern = 'Whisperly*.dmg'; Extra = $null; Manifest = 'mac-latest.json'; TagPrefix = 'v'; Name = 'Mac' }
}[$Platform]

# The app refuses a manifest larger than this (UpdateChecker.MaxManifestBytes)
# and a version that does not match this shape (UpdatePolicy.VersionShape).
$maxManifestBytes = 16 * 1024
$versionShape = '^\d{1,4}\.\d{1,4}(\.\d{1,6})?(-[0-9A-Za-z.\-]{1,32})?$'

function Step([string] $text) { Write-Host "==> $text" -ForegroundColor Cyan }

if ([bool]$FromTag -eq [bool]$File) { throw 'Pass exactly one of -FromTag or -File.' }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'The GitHub CLI (gh) is required: winget install GitHub.cli' }

# The manifest is committed from this checkout, so it has to be current and clean.
Step 'Checking this checkout'
& git -C $root pull --ff-only --quiet
if ($LASTEXITCODE -ne 0) { throw 'git pull failed. Commit or stash local changes first.' }
if (& git -C $root status --porcelain -- $spec.Manifest) { throw "$($spec.Manifest) has uncommitted changes." }

$work = Join-Path ([IO.Path]::GetTempPath()) "whisperly-publish-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
New-Item -ItemType Directory -Path $work | Out-Null
# gh writes UTF-8. PowerShell decodes it with the console's code page unless
# told otherwise, which turns the å in Danish release notes into garbage.
$consoleEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
try {
    $extraFile = $null
    $published = $null
    if ($FromTag) {
        Step "Downloading $FromTag from $SourceRepo"
        & gh release download $FromTag -R $SourceRepo -p $spec.Pattern -D $work
        if ($LASTEXITCODE -ne 0) { throw "Could not download $($spec.Pattern) from $SourceRepo@$FromTag." }
        $found = @(Get-ChildItem -LiteralPath $work -File)
        if ($found.Count -ne 1) { throw "Expected one file matching $($spec.Pattern) in $FromTag, found $($found.Count)." }
        $File = $found[0].FullName
        if ($spec.Extra) {
            & gh release download $FromTag -R $SourceRepo -p $spec.Extra -D $work 2>$null
            $candidate = Join-Path $work $spec.Extra
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $candidate)) { $extraFile = $candidate }
        }
        if (-not $Version) { $Version = $FromTag -replace '^(windows-|mac-|macos-)?v', '' }
        if (-not $PSBoundParameters.ContainsKey('Notes')) {
            # Native output arrives as an array of lines; keep them as lines.
            $Notes = (& gh release view $FromTag -R $SourceRepo --json body -q .body) -join "`n"
        }
        # The page says when a build came out, not when it was promoted here.
        $published = & gh release view $FromTag -R $SourceRepo --json publishedAt -q .publishedAt
    }
    else {
        if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "No such file: $File" }
        $File = (Resolve-Path -LiteralPath $File).Path
        if (-not $Version -and ((Split-Path -Leaf $File) -match 'v?(\d+\.\d+(\.\d+)?(-[0-9A-Za-z.\-]+)?)\.(exe|dmg)$')) { $Version = $Matches[1] }
    }

    # Invariant culture: on a Danish system ':' in a format string becomes '.',
    # which no browser parses as a time.
    if (-not $published) {
        $published = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH':'mm':'ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
    }

    if (-not $Version) { throw 'Could not tell the version from the tag or file name. Pass -Version.' }
    if ($Version -notmatch $versionShape) { throw "'$Version' is not a version the app would accept." }

    # Refuse a file that is obviously not what it claims to be before it becomes public.
    Step 'Checking the file'
    $item = Get-Item -LiteralPath $File
    if ($item.Length -lt 1MB) { throw "$($item.Name) is only $($item.Length) bytes; that is not a Whisperly build." }
    $stream = [IO.File]::OpenRead($File)
    try {
        $head = New-Object byte[] 2
        [void]$stream.Read($head, 0, 2)
        $tail = New-Object byte[] 4
        [void]$stream.Seek(-512, [IO.SeekOrigin]::End)
        [void]$stream.Read($tail, 0, 4)
    }
    finally { $stream.Dispose() }
    if ($Platform -eq 'windows') {
        if ([Text.Encoding]::ASCII.GetString($head) -ne 'MZ') { throw "$($item.Name) is not a Windows executable." }
        $productVersion = $item.VersionInfo.ProductVersion
        if ($productVersion -and -not $productVersion.StartsWith($Version)) {
            throw "$($item.Name) says it is version $productVersion, not $Version."
        }
    }
    elseif ([Text.Encoding]::ASCII.GetString($tail) -ne 'koly') {
        throw "$($item.Name) is not a disk image."
    }

    # Notes are public. GitHub's generated "What's Changed" list is made of
    # links into the private source repository, as are some hand-written
    # lines; a visitor would only ever get a 404 from them, so they go.
    if ($Notes -and (Test-Path -LiteralPath $Notes -PathType Leaf)) { $Notes = Get-Content -LiteralPath $Notes -Raw }
    $Notes = ([string]$Notes -split "`r?`n## What's Changed", 2)[0]
    $Notes = (($Notes -split "`r?`n") | Where-Object { $_ -notmatch 'github\.com/mbn-code/whisperly(?![\w-])' }) -join "`n"
    $Notes = ($Notes -replace "`n{3,}", "`n`n").Trim()

    $tag = "$($spec.TagPrefix)$Version"
    & gh release view $tag -R $repo --json tagName 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { throw "$tag is already published in $repo." }

    $name = $item.Name
    $sha256 = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLowerInvariant()

    # The page shows the file's real hash beside the notes. A different hash
    # quoted in the notes - say from a build that CI later replaced - would
    # read as a tampered download.
    foreach ($quoted in [regex]::Matches($Notes, '\b[0-9a-fA-F]{64}\b')) {
        if ($quoted.Value.ToLowerInvariant() -ne $sha256) {
            throw "The notes quote SHA-256 $($quoted.Value), but $name is $sha256. Fix the notes (-Notes) and run again."
        }
    }
    $sidecar = Join-Path $work "$name.sha256"
    [IO.File]::WriteAllText($sidecar, "$sha256  $name`n")
    $assets = @($File, $sidecar)
    if ($extraFile) { $assets += $extraFile }

    $url = "https://github.com/$repo/releases/download/$tag/$name"
    $manifest = [ordered]@{
        version     = $Version
        url         = $url
        sha256      = $sha256
        bytes       = $item.Length
        file        = $name
        tag         = $tag
        publishedAt = $published
        notes       = $Notes
    }
    $json = ($manifest | ConvertTo-Json -Depth 3) + "`n"
    $jsonBytes = [Text.Encoding]::UTF8.GetByteCount($json)
    if ($jsonBytes -gt $maxManifestBytes) {
        throw "The manifest would be $jsonBytes bytes; the app refuses anything over $maxManifestBytes. Shorten the notes."
    }

    Write-Host ''
    Write-Host "Platform  $($spec.Name)"
    Write-Host "Version   $Version"
    Write-Host "Tag       $tag"
    Write-Host "File      $name ($([Math]::Round($item.Length / 1MB, 1)) MB)"
    if ($extraFile) { Write-Host "Also      $(Split-Path -Leaf $extraFile) ($([Math]::Round((Get-Item -LiteralPath $extraFile).Length / 1MB, 1)) MB)" }
    Write-Host "SHA-256   $sha256"
    Write-Host ''
    Write-Host $(if ($Notes) { $Notes } else { '(no notes)' }) -ForegroundColor DarkGray
    Write-Host ''
    if ($WhatIfOnly) { Write-Host 'Checks only - nothing was published.'; return }

    Step "Creating release $tag"
    $notesFile = Join-Path $work 'notes.md'
    [IO.File]::WriteAllText($notesFile, $(if ($Notes) { $Notes } else { "Whisperly $Version for $($spec.Name)." }))
    # Windows 0.x builds are previews, marked as pre-releases the way the source
    # repository marks them.
    $flags = @()
    if ($Platform -eq 'windows' -and $Version -match '^0\.') { $flags += '--prerelease' }
    & gh release create $tag @assets -R $repo --target main --title "Whisperly $Version for $($spec.Name)" --notes-file $notesFile @flags
    if ($LASTEXITCODE -ne 0) { throw 'gh release create failed. Nothing was committed; delete the release by hand if it was half-created.' }

    # Exactly the request a visitor makes: no account, redirects followed.
    Step 'Checking the download works without an account'
    $ok = $false
    foreach ($attempt in 1..10) {
        try {
            $response = Invoke-WebRequest -Uri $url -Method Head -MaximumRedirection 5 -UseBasicParsing
            if ($response.StatusCode -eq 200) { $ok = $true; break }
        }
        catch { }
        Start-Sleep -Seconds 3
    }
    if (-not $ok) { throw "$url does not download anonymously. The release exists, but the manifest was NOT updated." }

    Step "Publishing $($spec.Manifest)"
    [IO.File]::WriteAllText((Join-Path $root $spec.Manifest), $json, (New-Object Text.UTF8Encoding $false))
    & git -C $root add -- $spec.Manifest
    & git -C $root commit --quiet -m "Publish Whisperly $Version for $($spec.Name)"
    if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }
    & git -C $root push --quiet origin main
    if ($LASTEXITCODE -ne 0) { throw 'git push failed. The release is up; push the manifest commit by hand.' }

    Write-Host ''
    Write-Host "Published. The site picks it up once Pages rebuilds, usually within a minute."
    Write-Host "Site      $siteUrl"
    Write-Host "Release   https://github.com/$repo/releases/tag/$tag"
}
finally {
    [Console]::OutputEncoding = $consoleEncoding
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
