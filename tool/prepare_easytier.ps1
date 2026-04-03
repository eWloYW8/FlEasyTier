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
$bundleDir = Join-Path $crateDir 'third_party\x86_64'

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
if (!(Test-Path $bundleDir)) {
  throw "EasyTier bundled runtime directory not found at $bundleDir"
}

$bundleFiles = Get-ChildItem -Path $bundleDir -File
if ($bundleFiles.Count -eq 0) {
  throw "No bundled runtime files found in $bundleDir"
}

foreach ($bundleFile in $bundleFiles) {
  Copy-Item $bundleFile.FullName (Join-Path $outputDirPath $bundleFile.Name) -Force
}
