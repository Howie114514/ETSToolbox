#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$EtsDir = "${env:ProgramFiles(x86)}\ETS",
    [ValidateRange(1, 1440)][int]$Minutes = 30,
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Get-Location) 'ETSToolbox-crash-diagnostics.txt'
}

function Get-PeMachine {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    $reader = New-Object System.IO.BinaryReader($stream)
    try {
        $stream.Position = 0x3C
        $peOffset = $reader.ReadUInt32()
        $stream.Position = $peOffset + 4
        switch ($reader.ReadUInt16()) {
            0x014C { return 'x86' }
            0x8664 { return 'x64' }
            0xAA64 { return 'arm64' }
            default { return 'unknown' }
        }
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Collected: $(Get-Date -Format o)")
$lines.Add("Windows: $([Environment]::OSVersion.VersionString)")

foreach ($name in @('ETSShell.exe', 'winmm.dll')) {
    $path = Join-Path $EtsDir $name
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $item = Get-Item -LiteralPath $path
        $lines.Add("$name path: $path")
        $lines.Add("$name architecture: $(Get-PeMachine -Path $path)")
        $lines.Add("$name SHA-256: $((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash)")
        $lines.Add("$name modified: $($item.LastWriteTime.ToString('o'))")
    }
    else {
        $lines.Add("$name missing: $path")
    }
}

$lines.Add('Recent backups:')
$backups = @(Get-ChildItem -LiteralPath $EtsDir -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'ETSToolbox.backup-*' -or $_.Name -like 'winmm.dll.backup-*' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 10)
if ($backups.Count -eq 0) {
    $lines.Add('  none')
}
else {
    foreach ($backup in $backups) {
        $lines.Add("  $($backup.FullName) | $($backup.LastWriteTime.ToString('o'))")
    }
}

$lines.Add("Application events from the last $Minutes minute(s):")
$since = (Get-Date).AddMinutes(-$Minutes)
try {
    $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $since } -ErrorAction Stop |
        Where-Object { $_.Message -match 'ETSShell|winmm|ETSToolbox' } |
        Select-Object -First 20)
    if ($events.Count -eq 0) {
        $lines.Add('  no matching events')
    }
    else {
        foreach ($event in $events) {
            $lines.Add('')
            $lines.Add("TimeCreated: $($event.TimeCreated.ToString('o'))")
            $lines.Add("Provider: $($event.ProviderName)")
            $lines.Add("EventId: $($event.Id)")
            $lines.Add("Level: $($event.LevelDisplayName)")
            $lines.Add('Message:')
            $lines.Add($event.Message)
        }
    }
}
catch {
    $lines.Add("  event query failed: $($_.Exception.Message)")
}

$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
$lines | Set-Content -LiteralPath $resolvedOutput -Encoding UTF8
Write-Host "Diagnostics saved: $resolvedOutput"
