$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir '..')
$easyTierRoot = Resolve-Path (Join-Path $repoRoot 'third_party/EasyTier')
$jniRoot = Resolve-Path (Join-Path $easyTierRoot 'easytier-contrib/easytier-android-jni')
$outputRoot = Join-Path $repoRoot 'android/app/src/main/jniLibs'

$targetMap = @{
  'arm64-v8a' = 'aarch64-linux-android'
  'armeabi-v7a' = 'armv7-linux-androideabi'
  'x86' = 'i686-linux-android'
  'x86_64' = 'x86_64-linux-android'
}

$androidTargets = @('arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64')
if ($env:FLEASYTIER_ANDROID_ABIS) {
  $androidTargets = $env:FLEASYTIER_ANDROID_ABIS.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
  throw 'cargo is required to build EasyTier Android JNI/FFI libraries'
}

try {
  cargo ndk --version | Out-Null
} catch {
  cargo install cargo-ndk
}

foreach ($androidTarget in $androidTargets) {
  if (-not $targetMap.ContainsKey($androidTarget)) {
    throw "Unsupported Android ABI: $androidTarget"
  }
  rustup target add $targetMap[$androidTarget] | Out-Null
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

Push-Location $easyTierRoot
try {
  foreach ($androidTarget in $androidTargets) {
    $rustTarget = $targetMap[$androidTarget]
    Write-Host "Building easytier-ffi for $androidTarget ($rustTarget)"
    cargo ndk -t $androidTarget build --release --manifest-path (Join-Path $easyTierRoot 'easytier-contrib/easytier-ffi/Cargo.toml')
    Write-Host "Building easytier-android-jni for $androidTarget ($rustTarget)"
    $nativeLibDir = Join-Path $easyTierRoot "target/$rustTarget/release"
    $oldRustFlags = $env:RUSTFLAGS
    $env:RUSTFLAGS = (($oldRustFlags, "-L native=$nativeLibDir", "-l dylib=easytier_ffi") | Where-Object { $_ -and $_.Trim() }) -join ' '
    try {
      cargo ndk -t $androidTarget build --release --manifest-path (Join-Path $jniRoot 'Cargo.toml')
    } finally {
      $env:RUSTFLAGS = $oldRustFlags
    }

    $jniLib = Join-Path $easyTierRoot "target/$rustTarget/release/libeasytier_android_jni.so"
    $ffiLib = Join-Path $easyTierRoot "target/$rustTarget/release/libeasytier_ffi.so"
    if (-not (Test-Path $jniLib)) {
      throw "Built JNI library not found at $jniLib"
    }
    if (-not (Test-Path $ffiLib)) {
      throw "Built FFI library not found at $ffiLib"
    }

    $targetDir = Join-Path $outputRoot $androidTarget
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    Copy-Item $jniLib (Join-Path $targetDir 'libeasytier_android_jni.so') -Force
    Copy-Item $ffiLib (Join-Path $targetDir 'libeasytier_ffi.so') -Force
  }
} finally {
  Pop-Location
}

Write-Host "Embedded Android JNI/FFI libraries prepared in $outputRoot"
