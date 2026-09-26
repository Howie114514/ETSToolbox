#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$EtsDir = "${env:ProgramFiles(x86)}\ETS",
    [string]$VcpkgRoot = $env:VCPKG_ROOT,
    [switch]$Deploy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $utf8NoBom
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom
$env:VSLANG = '1033'
& "$env:SystemRoot\System32\chcp.com" 65001 | Out-Null

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($ArgumentList -join ' ')"
    }
}

function Get-PeMachine {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
    )
    $reader = New-Object System.IO.BinaryReader($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            throw "Not a PE file (missing MZ signature): $Path"
        }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadUInt32()
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "Not a PE file (missing PE signature): $Path"
        }
        $machine = $reader.ReadUInt16()
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }

    switch ($machine) {
        0x014C { return 'x86' }
        0x8664 { return 'x64' }
        0xAA64 { return 'arm64' }
        default { return ('unknown-0x{0:X4}' -f $machine) }
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$etsShell = Join-Path $EtsDir 'ETSShell.exe'
$installedDll = Join-Path $EtsDir 'winmm.dll'

if (-not (Test-Path -LiteralPath $etsShell -PathType Leaf)) {
    throw "ETSShell.exe was not found: $etsShell"
}

$targetMachine = Get-PeMachine -Path $etsShell
Write-Host "ETSShell.exe PE architecture: $targetMachine"
if ($targetMachine -ne 'x86') {
    throw "Unsupported ETSShell.exe architecture: $targetMachine. This source tree contains MSVC x86 inline-assembly proxy stubs and must not be deployed to a non-x86 process."
}

$requiredSubmoduleFiles = @(
    (Join-Path $repoRoot 'cef\include\capi\cef_client_capi.h'),
    (Join-Path $repoRoot 'cpp-httplib\httplib.h')
)
foreach ($requiredFile in $requiredSubmoduleFiles) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Missing submodule file: $requiredFile. Run: git submodule update --init --recursive"
    }
}

$cmake = (Get-Command cmake.exe -ErrorAction Stop).Source
if ([string]::IsNullOrWhiteSpace($VcpkgRoot)) {
    throw 'VCPKG_ROOT is not set. Point it to an official standalone vcpkg checkout.'
}
$vcpkg = Join-Path $VcpkgRoot 'vcpkg.exe'
$toolchain = Join-Path $VcpkgRoot 'scripts\buildsystems\vcpkg.cmake'
if (-not (Test-Path -LiteralPath $vcpkg -PathType Leaf)) {
    throw "vcpkg.exe was not found: $vcpkg"
}
if (-not (Test-Path -LiteralPath $toolchain -PathType Leaf)) {
    throw "vcpkg CMake toolchain was not found: $toolchain"
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
    throw "vswhere.exe was not found: $vswhere. Install Visual Studio 2022 C++ build tools, CMake tools, and a Windows SDK."
}
$vsInstall = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace($vsInstall)) {
    throw 'No Visual Studio installation with the MSVC x86/x64 build tools was found.'
}

$vcToolsVersionFile = Join-Path $vsInstall 'VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt'
if (-not (Test-Path -LiteralPath $vcToolsVersionFile -PathType Leaf)) {
    throw "MSVC toolset version file was not found: $vcToolsVersionFile"
}
$vcToolsVersion = (Get-Content -LiteralPath $vcToolsVersionFile -Raw).Trim()
$dumpbin = Join-Path $vsInstall "VC\Tools\MSVC\$vcToolsVersion\bin\Hostx64\x86\dumpbin.exe"
if (-not (Test-Path -LiteralPath $dumpbin -PathType Leaf)) {
    throw "x86 dumpbin.exe was not found: $dumpbin"
}

$cmakeHelp = (& $cmake --help | Out-String)
$generatorMatch = [regex]::Match($cmakeHelp, 'Visual Studio \d+ \d{4}')
if (-not $generatorMatch.Success) {
    throw 'This CMake installation does not list a Visual Studio generator.'
}
$generator = $generatorMatch.Value
$triplet = 'x86-windows'
$buildDir = Join-Path $repoRoot 'out\build\windows-x86-release'

Write-Host "Visual Studio: $vsInstall"
Write-Host "CMake generator: $generator"
Write-Host "vcpkg triplet: $triplet"

Invoke-Checked -FilePath $vcpkg -ArgumentList @('install', "detours:$triplet")
$detoursInclude = Join-Path $VcpkgRoot "installed\$triplet\include"
$detoursLibrary = Join-Path $VcpkgRoot "installed\$triplet\lib\detours.lib"
if (-not (Test-Path -LiteralPath $detoursInclude -PathType Container)) {
    throw "Detours include directory was not found: $detoursInclude"
}
if (-not (Test-Path -LiteralPath $detoursLibrary -PathType Leaf)) {
    throw "Release Detours library was not found: $detoursLibrary"
}
$configureArguments = @(
    '-S', $repoRoot,
    '-B', $buildDir,
    '-G', $generator,
    '-A', 'Win32',
    "-DVCPKG_TARGET_TRIPLET=$triplet",
    "-DDETOURS_INCLUDE_DIRS=$detoursInclude",
    "-DDETOURS_LIBRARY=$detoursLibrary",
    '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL'
)
if (-not (Test-Path -LiteralPath (Join-Path $buildDir 'CMakeCache.txt') -PathType Leaf)) {
    $configureArguments += "-DCMAKE_TOOLCHAIN_FILE=$toolchain"
}
Invoke-Checked -FilePath $cmake -ArgumentList $configureArguments
Invoke-Checked -FilePath $cmake -ArgumentList @('--build', $buildDir, '--config', 'Release', '--target', 'ETSToolbox')

$builtCandidates = @(Get-ChildItem -LiteralPath $buildDir -Filter 'winmm.dll' -File -Recurse | Where-Object { $_.FullName -match '[\\/]Release[\\/]winmm\.dll$' })
if ($builtCandidates.Count -ne 1) {
    throw "Expected one Release winmm.dll under $buildDir, found $($builtCandidates.Count)."
}
$builtDll = $builtCandidates[0].FullName
$builtMachine = Get-PeMachine -Path $builtDll
if ($builtMachine -ne $targetMachine) {
    throw "Architecture mismatch: ETSShell.exe is $targetMachine but built winmm.dll is $builtMachine."
}

$headers = @(& $dumpbin /nologo /headers $etsShell 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "dumpbin /headers failed for $etsShell"
}
$headersPath = Join-Path $buildDir 'ETSShell-headers.txt'
$headers | Set-Content -LiteralPath $headersPath -Encoding UTF8

$dependents = @(& $dumpbin /nologo /dependents $builtDll 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "dumpbin /dependents failed for $builtDll"
}
$dependentsPath = Join-Path $buildDir 'winmm-dependents.txt'
$dependents | Set-Content -LiteralPath $dependentsPath -Encoding UTF8

$forbiddenDependencies = @('VCRUNTIME140D.dll', 'MSVCP140D.dll', 'ucrtbased.dll')
$dependencyText = $dependents -join "`n"
$foundForbidden = @($forbiddenDependencies | Where-Object { $dependencyText -match [regex]::Escape($_) })
if ($foundForbidden.Count -gt 0) {
    throw "Release dependency check failed; Debug CRT imports remain: $($foundForbidden -join ', ')"
}

$builtHash = (Get-FileHash -LiteralPath $builtDll -Algorithm SHA256).Hash
Write-Host "Release DLL: $builtDll"
Write-Host "Release DLL SHA-256: $builtHash"
Write-Host "Dependency report: $dependentsPath"
Write-Host 'Debug CRT dependency check: PASS'

if (-not $Deploy) {
    Write-Host 'Deployment skipped. Re-run with -Deploy after reviewing the reports.'
    exit 0
}

if (-not (Test-Path -LiteralPath $installedDll -PathType Leaf)) {
    throw "Existing winmm.dll was not found, so no replacement was performed: $installedDll"
}
if (Get-Process -Name 'ETSShell' -ErrorAction SilentlyContinue) {
    throw 'ETSShell.exe is running. Close it before deployment; the script will not stop or start it.'
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDll = Join-Path $EtsDir "winmm.dll.backup-$timestamp"
if (Test-Path -LiteralPath $backupDll) {
    throw "Backup path already exists: $backupDll"
}

$oldHash = (Get-FileHash -LiteralPath $installedDll -Algorithm SHA256).Hash
Copy-Item -LiteralPath $installedDll -Destination $backupDll -ErrorAction Stop
$backupHash = (Get-FileHash -LiteralPath $backupDll -Algorithm SHA256).Hash
if ($backupHash -ne $oldHash) {
    throw "Backup hash mismatch. The installed DLL was not replaced. Backup: $backupDll"
}

try {
    Copy-Item -LiteralPath $builtDll -Destination $installedDll -Force -ErrorAction Stop
    $installedHash = (Get-FileHash -LiteralPath $installedDll -Algorithm SHA256).Hash
    if ($installedHash -ne $builtHash) {
        throw 'Post-deployment hash mismatch.'
    }
}
catch {
    try {
        Copy-Item -LiteralPath $backupDll -Destination $installedDll -Force -ErrorAction Stop
    }
    catch {
        throw "Deployment failed and automatic restore also failed. Restore the verified backup manually: $backupDll"
    }
    throw "Deployment failed; the original DLL was restored from: $backupDll"
}

Write-Host "Installed DLL: $installedDll"
Write-Host "Backup DLL: $backupDll"
Write-Host 'Deployment hash check: PASS'
Write-Host 'ETSShell.exe was not started. You may now test it manually.'
