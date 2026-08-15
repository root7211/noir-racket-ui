#!/usr/bin/env bash
# Read-only WSL Vulkan / Dozen / wgpu 30 visibility report.
# This script deliberately installs nothing and does not set persistent ICD overrides.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/wgpu-verify/Cargo.toml"
PROBE="$ROOT/wgpu-verify/target/release/noir_wgpu_probe"

section() { printf '\n===== %s =====\n' "$1"; }
command_path() { command -v "$1" 2>/dev/null || printf 'not-found'; }

section "host"
printf 'kernel='; uname -srmo
printf 'distro='; (grep -E '^(PRETTY_NAME|NAME|VERSION)=' /etc/os-release || true) | tr '\n' ';'; printf '\n'
printf 'wsl_interop='; test -e /proc/sys/fs/binfmt_misc/WSLInterop && printf 'present\n' || printf 'absent\n'
printf 'dxg_device='; test -e /dev/dxg && printf 'present\n' || printf 'absent\n'
printf 'wslg_runtime='; test -d /mnt/wslg && printf 'present\n' || printf 'absent\n'

section "commands"
for command in cargo rustc vulkaninfo nvidia-smi glxinfo; do
  printf '%s=%s\n' "$command" "$(command_path "$command")"
done
cargo --version 2>/dev/null || true
rustc --version 2>/dev/null || true

section "environment"
for name in WGPU_BACKEND WGPU_ADAPTER_NAME WGPU_POWER_PREF VK_ICD_FILENAMES VK_LAYER_PATH LD_LIBRARY_PATH DISPLAY WAYLAND_DISPLAY; do
  printf '%s=%q\n' "$name" "${!name-}"
done

section "vulkan_icd_inventory"
for directory in /usr/share/vulkan/icd.d /etc/vulkan/icd.d; do
  if test -d "$directory"; then
    find "$directory" -maxdepth 1 -type f -name '*.json' -printf '%f\n' | sort | sed "s|^|$directory/|"
  fi
done

section "vulkaninfo_summary"
if command -v vulkaninfo >/dev/null 2>&1; then
  vulkaninfo --summary 2>&1 | sed -n '1,220p'
else
  printf 'vulkaninfo is unavailable; install the distribution package usually named vulkan-tools, then rerun.\n'
fi

section "wgpu30_vulkan_probe"
if ! test -x "$PROBE"; then
  printf 'building noir_wgpu_probe with project rust-toolchain...\n'
  (cd "$ROOT" && cargo build --manifest-path "$MANIFEST" --release --bin noir_wgpu_probe)
fi
WGPU_BACKEND=vulkan "$PROBE"

section "wgpu30_all_backend_probe"
"$PROBE"

section "interpretation"
cat <<'TEXT'
PASS requires at least one adapter line with backend=Vulkan and type=DiscreteGpu or IntegratedGpu.
A backend=Vulkan type=Cpu line (for example llvmpipe) proves Vulkan is installed but does not prove physical-GPU access.
If /dev/dxg is absent, the WSL guest has no Windows GPU paravirtualization device; wgpu version changes cannot repair that.
If /dev/dxg is present but the Vulkan-only probe lists only Cpu adapters, collect this report before changing VK_ICD_FILENAMES. The likely boundary is the Windows GPU driver, Mesa/Dozen ICD, or the active WSL distribution rather than Noir's Scene or list ABI.
Do not persistently force a dzn ICD before the unforced report is saved: an ICD override can hide a working native Vulkan path or turn an adapter-selection issue into a loader issue.
TEXT
