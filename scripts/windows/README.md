# Windows portable EXE packaging

This folder contains `make-sfx.ps1`, a PowerShell script that packages the Flutter Windows app into a single self-extracting EXE. Users can double‑click the EXE to run the app immediately (no installer).

## Prerequisites (local Windows machine)
- Windows 10/11 x64
- Visual Studio 2022 with the "Desktop development with C++" workload (required by Flutter for Windows)
- Flutter SDK (stable channel) and Dart
- 7‑Zip installed (provides `7z.exe` and `7zsd.sfx`)
  - Recommended: `choco install 7zip`

## Build and package

Run in PowerShell from the repository root (on Windows only):

```
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
./scripts/windows/make-sfx.ps1
```

Outputs a single EXE under:

```
apps/flutter_demo/releases/windows/<name>-<version>-windows-x64-portable.exe
```

If bạn đang ở Linux/macOS, hãy dùng CI workflow thay vì chạy script trực tiếp. Vào GitHub → Actions → chạy workflow `windows-portable` và tải artifact EXE.

Use `-SkipBuild` to package an existing build (Windows):

```
./scripts/windows/make-sfx.ps1 -SkipBuild
```

Use `-ProjectDir` to target a different Flutter app directory (must contain `pubspec.yaml`):
Specify a custom output EXE path (Windows PowerShell requires escaping backslashes or using double quotes):

```
./scripts/windows/make-sfx.ps1 -OutputPath "$pwd\apps\flutter_demo\releases\MerkleKV-Mobile.exe"
```

```
./scripts/windows/make-sfx.ps1 -ProjectDir .\apps\flutter_demo
```

## Notes
- The EXE extracts to a temporary folder and launches the app, then cleans up after exit.
- If `7z.exe` or `7zsd.sfx/7z.sfx` is not found, install 7‑Zip and re-run.
- For CI builds, see `.github/workflows/windows-portable.yml`, which produces an artifact automatically.