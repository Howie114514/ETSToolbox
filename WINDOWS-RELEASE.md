# Windows Release build and replacement

This repair must be completed on the Windows computer that contains the real ETS installation. The script reads the PE machine field from `ETSShell.exe`; it does not infer the architecture from `Program Files (x86)`.

## Prerequisites

- Visual Studio 2022 or later with Desktop development with C++, MSVC x86/x64 build tools, CMake tools, and a Windows 10 or 11 SDK.
- An official standalone [vcpkg](https://github.com/microsoft/vcpkg) checkout with `VCPKG_ROOT` set to its root directory.
- PowerShell 5.1 or later.

The script installs the matching `detours:x86-windows` vcpkg port, configures CMake with the Visual Studio generator, builds `Release`, verifies the PE architecture, and runs `dumpbin /dependents`.

## Build and inspect only

Open PowerShell in this repository and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-release.ps1
```

The generated DLL and inspection reports are placed under `out\build\windows-x86-release`. No ETS files are changed in this mode.

## Build, verify, back up, and replace

Close E听说, open an elevated PowerShell in this repository, and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-release.ps1 -Deploy
```

For a non-default installation directory, also pass `-EtsDir 'D:\path\to\ETS'`.

Deployment occurs only after all of these checks pass:

- `ETSShell.exe` exists and its PE architecture is x86.
- The CEF and cpp-httplib submodule files exist.
- MSVC, a Visual Studio CMake generator, vcpkg, and x86 `dumpbin.exe` are available.
- The built `winmm.dll` architecture matches `ETSShell.exe`.
- `dumpbin /dependents` contains none of `VCRUNTIME140D.dll`, `MSVCP140D.dll`, or `ucrtbased.dll`.
- E听说 is not running and the existing `winmm.dll` was backed up with a matching SHA-256 hash.

The script does not start `ETSShell.exe`. Test it manually after the script reports the installed DLL path, backup path, and successful post-deployment hash check.
