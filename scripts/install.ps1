[CmdletBinding()]
param(
    [string]$EtsRoot = 'C:\Program Files (x86)\ETS',
    [string]$PackageRoot,
    [switch]$SkipAdministratorCheck,
    [switch]$SkipProcessCheck
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    throw 'The package directory could not be resolved. Pass -PackageRoot explicitly.'
}

if (-not $SkipAdministratorCheck) {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
            throw 'The installer path could not be resolved for administrator elevation.'
        }

        $elevationArguments = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', ('"{0}"' -f $PSCommandPath),
            '-EtsRoot', ('"{0}"' -f $EtsRoot),
            '-PackageRoot', ('"{0}"' -f $PackageRoot)
        )
        if ($SkipProcessCheck) {
            $elevationArguments += '-SkipProcessCheck'
        }

        Write-Host 'Requesting administrator permission...'
        $elevatedProcess = Start-Process `
            -FilePath 'powershell.exe' `
            -Verb RunAs `
            -ArgumentList $elevationArguments `
            -Wait `
            -PassThru
        if ($elevatedProcess.ExitCode -ne 0) {
            throw "The elevated installer exited with code $($elevatedProcess.ExitCode)."
        }
        Write-Host 'The elevated installer completed successfully.'
        exit 0
    }
}

if (-not $SkipProcessCheck -and (Get-Process -Name ETSShell -ErrorAction SilentlyContinue)) {
    throw 'ETSShell.exe is still running. Exit the application and try again.'
}

if (-not (Test-Path -LiteralPath (Join-Path $EtsRoot 'ETSShell.exe') -PathType Leaf)) {
    throw "ETSShell.exe was not found: $EtsRoot"
}

$requiredFiles = @(
    'winmm.dll',
    'etstoolbox/index.js',
    'etstoolbox/index.iframe.js',
    'etstoolbox/css/index.css',
    'etstoolbox/resources/logo.png',
    'etstoolbox/answer-console.ps1',
    'etstoolbox/open-answer-console.cmd'
)

$manifestPath = Join-Path $PackageRoot 'SHA256SUMS.txt'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Checksum manifest was not found: $manifestPath"
}

$manifest = [ordered]@{}
foreach ($line in Get-Content -LiteralPath $manifestPath) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -notmatch '^([0-9A-Fa-f]{64})\s{2}(.+)$') {
        throw "Invalid checksum line: $line"
    }
    $relative = $Matches[2].Replace('\', '/')
    if ([IO.Path]::IsPathRooted($relative) -or $relative.Split('/') -contains '..') {
        throw "Unsafe path in checksum manifest: $relative"
    }
    $manifest[$relative] = $Matches[1].ToUpperInvariant()
}

foreach ($relative in $requiredFiles) {
    if (-not $manifest.Contains($relative)) {
        throw "Required file is absent from checksum manifest: $relative"
    }
    $source = Join-Path $PackageRoot ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Package file is missing: $source"
    }
    $actualHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if ($actualHash -ne $manifest[$relative]) {
        throw "Package hash mismatch: $source`nExpected: $($manifest[$relative])`nActual: $actualHash"
    }
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$backupRoot = Join-Path $EtsRoot "ETSToolbox.backup-$timestamp"
$existingFiles = @{}
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

try {
    foreach ($relative in $requiredFiles) {
        $nativeRelative = $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)
        $target = Join-Path $EtsRoot $nativeRelative
        $backup = Join-Path $backupRoot $nativeRelative
        $existingFiles[$relative] = Test-Path -LiteralPath $target -PathType Leaf
        if ($existingFiles[$relative]) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
            Copy-Item -LiteralPath $target -Destination $backup -Force
        }
    }

    foreach ($relative in $requiredFiles) {
        $nativeRelative = $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)
        $source = Join-Path $PackageRoot $nativeRelative
        $target = Join-Path $EtsRoot $nativeRelative
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
        $installedHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        if ($installedHash -ne $manifest[$relative]) {
            throw "Installed file hash mismatch: $target"
        }
    }
}
catch {
    foreach ($relative in $requiredFiles) {
        if (-not $existingFiles.ContainsKey($relative)) { continue }
        $nativeRelative = $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)
        $target = Join-Path $EtsRoot $nativeRelative
        $backup = Join-Path $backupRoot $nativeRelative
        if ($existingFiles[$relative] -and (Test-Path -LiteralPath $backup -PathType Leaf)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath $backup -Destination $target -Force
        }
        elseif ($existingFiles[$relative] -eq $false -and (Test-Path -LiteralPath $target -PathType Leaf)) {
            Remove-Item -LiteralPath $target -Force
        }
    }
    throw
}

Write-Host "ETSToolbox installed: $EtsRoot"
Write-Host "Original files backup: $backupRoot"
Write-Host 'ETSShell.exe was not started. You may now test it manually.'
