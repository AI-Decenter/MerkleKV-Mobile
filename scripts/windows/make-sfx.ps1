#!/usr/bin/env pwsh
<#!
.SYNOPSIS
	Build a self-extracting portable EXE for the Flutter Windows app.

.DESCRIPTION
	This script packages the Flutter Windows release build output (the entire
	build/windows/x64/runner/Release directory) into a single self-extracting
	executable. When a user double-clicks the EXE, it extracts to a temporary
	folder, launches the app immediately, and removes the temp files after exit.

	It relies on 7-Zip's SFX module (7z.sfx or 7zsd.sfx) to produce the EXE.
	You can install 7-Zip from https://www.7-zip.org/ or via Chocolatey:
		choco install 7zip

.PARAMETER ProjectDir
	Path to the Flutter app directory containing pubspec.yaml (default: apps/flutter_demo).

.PARAMETER OutputDir
	Path to place the final portable EXE (default: <ProjectDir>/releases/windows).

.PARAMETER SkipBuild
	If set, skip running 'flutter build windows'. Assumes an existing release build exists.

.EXAMPLE
	# Build the Windows app and create a portable EXE
	pwsh -File scripts/windows/make-sfx.ps1

.EXAMPLE
	# Use an existing build and output to a custom directory
	pwsh -File scripts/windows/make-sfx.ps1 -SkipBuild -OutputDir C:\dist
#>

[CmdletBinding()]
param(
	[string]$ProjectDir = $null,
	[string]$OutputDir = $null,
	[Alias('Output')][string]$OutputPath = $null,
	[switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ensure we're on Windows, as Flutter Windows build requires Windows toolchain
$onWindows = $false
try {
	if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) {
		$onWindows = [bool]$IsWindows
	} else {
		$onWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
	}
} catch {
	$onWindows = ($env:OS -like '*Windows*')
}
if (-not $onWindows) {
	Write-Error "This script builds a Windows desktop app and must be run on Windows.\nOptions:\n - Run on a Windows 10/11 machine with Flutter + Visual Studio installed.\n - Or trigger CI workflow .github/workflows/windows-portable.yml to build on Windows runner."
	exit 1
}

function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Warning $msg }
function Write-Err($msg)  { Write-Error $msg }

function Resolve-SevenZip() {
	# Try common locations and PATH
	$candidates = @()
	if ($env:ProgramFiles)        { $candidates += (Join-Path -Path $env:ProgramFiles        -ChildPath '7-Zip\7z.exe') }
	if ($env:ProgramW6432)        { $candidates += (Join-Path -Path $env:ProgramW6432        -ChildPath '7-Zip\7z.exe') }
	if (${env:ProgramFiles(x86)}) { $candidates += (Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath '7-Zip\7z.exe') }
	$candidates += '7z.exe'

	foreach ($p in $candidates) {
		try {
			$resolved = (Get-Command $p -ErrorAction Stop).Source
			if (Test-Path $resolved) { return $resolved }
		} catch {}
	}
	return $null
}

function Resolve-SfxModule([string]$sevenZipExe) {
	# Prefer 7zsd.sfx, fallback to 7z.sfx, typically adjacent to 7z.exe
	if (-not $sevenZipExe) { return $null }
	$baseDir = Split-Path -Parent $sevenZipExe
	$candidates = @(
		Join-Path $baseDir '7zsd.sfx',
		Join-Path $baseDir '7z.sfx'
	)
	foreach ($c in $candidates) {
		if (Test-Path $c) { return $c }
	}
	return $null
}

function Get-YamlScalar([string]$file, [string]$key, [string]$default = '') {
	if (-not (Test-Path $file)) { return $default }
	$pattern = "^\s*$([regex]::Escape($key))\s*:\s*(.+?)\s*$"
	$line = Select-String -Path $file -Pattern $pattern -SimpleMatch:$false | Select-Object -First 1
	if ($null -eq $line) { return $default }
	$value = $line.Matches[0].Groups[1].Value.Trim()
	# Remove quotes if present
	if ($value.StartsWith('"') -and $value.EndsWith('"')) { $value = $value.Trim('"') }
	if ($value.StartsWith("'") -and $value.EndsWith("'")) { $value = $value.Trim("'") }
	return $value
}

function Ensure-Dir([string]$dir) {
	if (-not (Test-Path $dir)) { [void](New-Item -ItemType Directory -Path $dir) }
}

# Determine default project directory if not provided
if (-not $ProjectDir) {
	$ProjectDir = Join-Path -Path $PSScriptRoot -ChildPath '..\..\apps\flutter_demo'
}

# Validate project directory
try {
	$ProjectDir = (Resolve-Path -Path $ProjectDir -ErrorAction Stop).Path
} catch {
	Write-Err "ProjectDir not found: $ProjectDir"
	exit 1
}
if (-not (Test-Path (Join-Path $ProjectDir 'pubspec.yaml'))) {
	Write-Err "pubspec.yaml not found in ProjectDir: $ProjectDir"
	exit 1
}

if (-not $OutputDir) { $OutputDir = Join-Path $ProjectDir 'releases' 'windows' }
Ensure-Dir $OutputDir

$pubspec = Join-Path $ProjectDir 'pubspec.yaml'
$appName  = Get-YamlScalar -file $pubspec -key 'name' -default 'app'
$version  = Get-YamlScalar -file $pubspec -key 'version' -default '0.0.0'

# Sanitize for filename
$safeVersion = $version -replace '[^0-9A-Za-z\.-]+','-'
$safeName    = $appName -replace '[^0-9A-Za-z_\.-]+','-'

if (-not $SkipBuild) {
	Write-Info "Building Flutter Windows release for $appName..."
	Push-Location $ProjectDir
	try {
		# Ensure dependencies
		& flutter --version | Out-Null
		& flutter pub get
		& flutter build windows --release
	} finally {
		Pop-Location
	}
} else {
	Write-Info 'SkipBuild enabled; using existing build output.'
}

$releaseDir = Join-Path $ProjectDir 'build' 'windows' 'x64' 'runner' 'Release'
if (-not (Test-Path $releaseDir)) {
	Write-Err "Windows Release folder not found: $releaseDir. Build the app first or remove -SkipBuild."
	exit 1
}

# Determine the app EXE name
$exeCandidates = @(Get-ChildItem -Path $releaseDir -Filter '*.exe' -File | Where-Object { $_.Name -notmatch 'flutter_tester|unittests' })
if ($exeCandidates.Count -eq 0) {
	Write-Err "No application .exe found in $releaseDir"
	exit 1
}

$exeFile = $exeCandidates | Where-Object { $_.BaseName -ieq $appName } | Select-Object -First 1
if (-not $exeFile) { $exeFile = $exeCandidates | Select-Object -First 1 }
Write-Info "Using entrypoint: $($exeFile.Name)"

$sevenZipExe = Resolve-SevenZip
if (-not $sevenZipExe) {
	Write-Err "7-Zip (7z.exe) not found. Please install 7-Zip (https://www.7-zip.org/) or 'choco install 7zip' and re-run."
	exit 1
}

$sfxModule = Resolve-SfxModule -sevenZipExe $sevenZipExe
if (-not $sfxModule) {
	Write-Err "7-Zip SFX module not found (7zsd.sfx or 7z.sfx). Ensure 7-Zip is fully installed."
	exit 1
}

Write-Info "7-Zip: $sevenZipExe"
Write-Info "SFX module: $sfxModule"

# Paths
$archivePath = Join-Path $OutputDir ("$safeName-$safeVersion-windows-x64.7z")
$configPath  = Join-Path $OutputDir ("$safeName-$safeVersion-sfx-config.txt")
$portableExe = Join-Path $OutputDir ("$safeName-$safeVersion-windows-x64-portable.exe")

# If -Output/-OutputPath is provided, override the final EXE path and adjust OutputDir accordingly
if ($OutputPath) {
	$resolvedOut = $OutputPath
	if (-not [System.IO.Path]::IsPathRooted($resolvedOut)) {
		$resolvedOut = Join-Path -Path (Get-Location) -ChildPath $resolvedOut
	}
	try {
		$resolvedOut = (Resolve-Path -Path $resolvedOut -ErrorAction Stop).Path
	} catch {
		# Path may not exist yet; keep as constructed path
	}
	$portableExe = $resolvedOut
	$OutputDir   = Split-Path -Parent $portableExe
	Ensure-Dir $OutputDir
	$archivePath = Join-Path $OutputDir ("$safeName-$safeVersion-windows-x64.7z")
	$configPath  = Join-Path $OutputDir ("$safeName-$safeVersion-sfx-config.txt")
}

# Create 7z archive from the contents of the Release directory
Write-Info "Creating 7z archive..."
Push-Location $releaseDir
try {
	if (Test-Path $archivePath) { Remove-Item -Force $archivePath }
	& $sevenZipExe a -t7z -mx9 -mmt=on -- $archivePath * | Out-Null
} finally {
	Pop-Location
}

# Create SFX configuration
$config = @"
;!@Install@!UTF-8!
Title="$appName $version"
GUIMode="2"
TempMode
RunProgram="$($exeFile.Name)"
;!@InstallEnd@!
"@
Set-Content -Path $configPath -Value $config -Encoding UTF8

# Compose final self-extracting EXE: SFX + config + archive
Write-Info "Assembling portable EXE..."
if (Test-Path $portableExe) { Remove-Item -Force $portableExe }

# Use classic copy /b to concatenate in correct order
$sfxQ = '"' + $sfxModule + '"'
$cfgQ = '"' + $configPath + '"'
$arcQ = '"' + $archivePath + '"'
$outQ = '"' + $portableExe + '"'

$cmd = "copy /b $sfxQ + $cfgQ + $arcQ $outQ > NUL"
cmd /c $cmd | Out-Null

if (-not (Test-Path $portableExe)) {
	Write-Err "Failed to create portable EXE at $portableExe"
	exit 1
}

Write-Host "\nSUCCESS: Portable EXE created:" -ForegroundColor Green
Write-Host "  $portableExe" -ForegroundColor Green
Write-Host "\nYou can distribute this single file. When launched, it extracts to a temp folder and runs $($exeFile.Name)." -ForegroundColor Green

