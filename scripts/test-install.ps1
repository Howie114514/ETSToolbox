$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function New-TestPackage([string]$Root) {
    $files = @(
        'winmm.dll',
        'etstoolbox/index.js',
        'etstoolbox/index.iframe.js',
        'etstoolbox/css/index.css',
        'etstoolbox/resources/logo.png',
        'etstoolbox/answer-console.ps1',
        'etstoolbox/open-answer-console.cmd'
    )
    $lines = foreach ($relative in $files) {
        $path = Join-Path $Root ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        [IO.File]::WriteAllText($path, "new:$relative")
        "{0}  {1}" -f (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant(), $relative
    }
    [IO.File]::WriteAllLines((Join-Path $Root 'SHA256SUMS.txt'), $lines)
}

function Invoke-TestInstall([string]$PackageRoot, [string]$EtsRoot) {
    & (Join-Path $PSScriptRoot 'install.ps1') `
        -PackageRoot $PackageRoot `
        -EtsRoot $EtsRoot `
        -SkipAdministratorCheck `
        -SkipProcessCheck
}

function Invoke-TestInstallWithDefaultPackageRoot([string]$PackageRoot, [string]$EtsRoot) {
    $packagedInstaller = Join-Path $PackageRoot 'install.ps1'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'install.ps1') -Destination $packagedInstaller -Force
    & $packagedInstaller `
        -EtsRoot $EtsRoot `
        -SkipAdministratorCheck `
        -SkipProcessCheck
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("etstoolbox-install-test-" + [Guid]::NewGuid().ToString('N'))
try {
    $packageRoot = Join-Path $testRoot 'package'
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
    New-TestPackage $packageRoot

    $missingDirectoryRoot = Join-Path $testRoot 'missing-directory'
    New-Item -ItemType Directory -Path $missingDirectoryRoot -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $missingDirectoryRoot 'ETSShell.exe'), 'test')
    Invoke-TestInstallWithDefaultPackageRoot $packageRoot $missingDirectoryRoot
    Assert-True (Test-Path -LiteralPath (Join-Path $missingDirectoryRoot 'etstoolbox/index.js') -PathType Leaf) 'missing etstoolbox directory was not created'
    Assert-True (Test-Path -LiteralPath (Join-Path $missingDirectoryRoot 'etstoolbox/css/index.css') -PathType Leaf) 'nested CSS directory was not created'

    $missingIndexRoot = Join-Path $testRoot 'missing-index'
    New-Item -ItemType Directory -Path (Join-Path $missingIndexRoot 'etstoolbox/css') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $missingIndexRoot 'ETSShell.exe'), 'test')
    [IO.File]::WriteAllText((Join-Path $missingIndexRoot 'etstoolbox/css/index.css'), 'old-css')
    Invoke-TestInstall $packageRoot $missingIndexRoot
    Assert-True (Test-Path -LiteralPath (Join-Path $missingIndexRoot 'etstoolbox/index.js') -PathType Leaf) 'missing index.js was not restored'
    Assert-True ((Get-Content -LiteralPath (Join-Path $missingIndexRoot 'etstoolbox/css/index.css') -Raw) -eq 'new:etstoolbox/css/index.css') 'existing CSS was not updated'
    $backupCss = Get-ChildItem -LiteralPath $missingIndexRoot -Filter 'ETSToolbox.backup-*' -Directory | ForEach-Object { Join-Path $_.FullName 'etstoolbox/css/index.css' } | Where-Object { Test-Path -LiteralPath $_ }
    Assert-True (($backupCss | Measure-Object).Count -eq 1) 'existing CSS was not backed up'

    Write-Host 'Installer tests: PASS (default package root, missing directory, missing index.js)'
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
