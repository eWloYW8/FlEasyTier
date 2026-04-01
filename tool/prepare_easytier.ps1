param(
  [Parameter(Mandatory = $true)]
  [string]$RepoRoot,

  [Parameter(Mandatory = $true)]
  [string]$OutputDir
)

$ErrorActionPreference = 'Stop'

$repoRootPath = (Resolve-Path $RepoRoot).Path
$outputDirInput = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
  $OutputDir
} else {
  Join-Path $repoRootPath $OutputDir
}
$outputDirPath = [System.IO.Path]::GetFullPath($outputDirInput)
$easyTierRoot = Join-Path $repoRootPath 'third_party\EasyTier'
$crateDir = Join-Path $easyTierRoot 'easytier'
$targetBin = Join-Path $easyTierRoot 'target\release\easytier-core.exe'

if (!(Test-Path $crateDir)) {
  throw "EasyTier submodule not found at $crateDir"
}

New-Item -ItemType Directory -Force -Path $outputDirPath | Out-Null

Push-Location $easyTierRoot
try {
  & cargo build --release -p easytier --bin easytier-core
} finally {
  Pop-Location
}

if (!(Test-Path $targetBin)) {
  throw "Built easytier-core not found at $targetBin"
}

Copy-Item $targetBin (Join-Path $outputDirPath 'easytier-core.exe') -Force

$cacheDir = Join-Path $repoRootPath '.dart_tool\embedded_tools\wintun'
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null

$version = '0.14.1'
$zipPath = Join-Path $cacheDir "wintun-$version.zip"
$extractDir = Join-Path $cacheDir "wintun-$version"
$downloadUrl = "https://www.wintun.net/builds/wintun-$version.zip"

if (!(Test-Path $zipPath)) {
  Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath
}

if (!(Test-Path $extractDir)) {
  Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
}

$wintunDll = Get-ChildItem -Path $extractDir -Recurse -Filter 'wintun.dll' |
  Where-Object { $_.FullName -match '(amd64|x64)' } |
  Select-Object -First 1

if ($null -eq $wintunDll) {
  throw "Unable to locate amd64 wintun.dll in $extractDir"
}

Copy-Item $wintunDll.FullName (Join-Path $outputDirPath 'wintun.dll') -Force
