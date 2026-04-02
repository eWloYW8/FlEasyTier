#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
EASYTIER_ROOT="${REPO_ROOT}/third_party/EasyTier"
OUTPUT_ROOT="${REPO_ROOT}/android/app/src/main/jniLibs"
JNI_ROOT="${EASYTIER_ROOT}/easytier-contrib/easytier-android-jni"

declare -A TARGET_MAP=(
  ["arm64-v8a"]="aarch64-linux-android"
  ["armeabi-v7a"]="armv7-linux-androideabi"
  ["x86"]="i686-linux-android"
  ["x86_64"]="x86_64-linux-android"
)

IFS=',' read -r -a ANDROID_TARGETS <<< "${FLEASYTIER_ANDROID_ABIS:-arm64-v8a,armeabi-v7a,x86,x86_64}"

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo is required to build EasyTier Android JNI/FFI libraries" >&2
  exit 1
fi

if ! cargo ndk --version >/dev/null 2>&1; then
  cargo install cargo-ndk
fi

for android_target in "${ANDROID_TARGETS[@]}"; do
  rust_target="${TARGET_MAP[$android_target]:-}"
  if [[ -z "${rust_target}" ]]; then
    echo "Unsupported Android ABI: ${android_target}" >&2
    exit 1
  fi
  rustup target add "${rust_target}"
done

mkdir -p "${OUTPUT_ROOT}"

pushd "${EASYTIER_ROOT}" >/dev/null
for android_target in "${ANDROID_TARGETS[@]}"; do
  rust_target="${TARGET_MAP[$android_target]}"
  echo "Building easytier-ffi for ${android_target} (${rust_target})"
  cargo ndk -t "${android_target}" build --release --manifest-path "${EASYTIER_ROOT}/easytier-contrib/easytier-ffi/Cargo.toml"
  echo "Building easytier-android-jni for ${android_target} (${rust_target})"
  native_lib_dir="${EASYTIER_ROOT}/target/${rust_target}/release"
  RUSTFLAGS="${RUSTFLAGS:-} -L native=${native_lib_dir} -l dylib=easytier_ffi" \
    cargo ndk -t "${android_target}" build --release --manifest-path "${JNI_ROOT}/Cargo.toml"

  jni_lib="${EASYTIER_ROOT}/target/${rust_target}/release/libeasytier_android_jni.so"
  ffi_lib="${EASYTIER_ROOT}/target/${rust_target}/release/libeasytier_ffi.so"
  if [[ ! -f "${jni_lib}" ]]; then
    echo "Built JNI library not found at ${jni_lib}" >&2
    exit 1
  fi
  if [[ ! -f "${ffi_lib}" ]]; then
    echo "Built FFI library not found at ${ffi_lib}" >&2
    exit 1
  fi

  target_dir="${OUTPUT_ROOT}/${android_target}"
  mkdir -p "${target_dir}"
  cp "${jni_lib}" "${target_dir}/libeasytier_android_jni.so"
  cp "${ffi_lib}" "${target_dir}/libeasytier_ffi.so"
done
popd >/dev/null

echo "Embedded Android JNI/FFI libraries prepared in ${OUTPUT_ROOT}"
