#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:?repo root required}"
output_dir="${2:?output dir required}"

repo_root="$(cd "$repo_root" && pwd)"
output_dir="$(mkdir -p "$output_dir" && cd "$output_dir" && pwd)"
easytier_root="$repo_root/third_party/EasyTier"
crate_dir="$easytier_root/easytier"
target_bin="$easytier_root/target/release/easytier-core"

if [[ ! -d "$crate_dir" ]]; then
  echo "EasyTier submodule not found at $crate_dir" >&2
  exit 1
fi

cd "$easytier_root"
cargo build --release -p easytier --bin easytier-core

if [[ ! -f "$target_bin" ]]; then
  echo "Built easytier-core not found at $target_bin" >&2
  exit 1
fi

cp "$target_bin" "$output_dir/easytier-core"
chmod +x "$output_dir/easytier-core"
