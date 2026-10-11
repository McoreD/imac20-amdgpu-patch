# Shared hardware preflight for the installer and imac20-hwaccel.
# The optional directory argument is for fixture tests; production callers use
# the kernel's PCI inventory, which works even when amdgpu failed to bind.
require_supported_gpu() {
  local pci_root=${1:-/sys/bus/pci/devices} device vendor id subvendor subdevice
  for device in "$pci_root"/*; do
    [[ -d $device ]] || continue
    vendor=$(cat "$device/vendor" 2>/dev/null) || continue
    id=$(cat "$device/device" 2>/dev/null) || continue
    subvendor=$(cat "$device/subsystem_vendor" 2>/dev/null) || continue
    subdevice=$(cat "$device/subsystem_device" 2>/dev/null) || continue
    # Match the bundled deferred-UCLK patch, not the marketing GPU name.
    if [[ $vendor == 0x1002 && $id == 0x7340 &&
          $subvendor == 0x106b && $subdevice == 0x0219 ]]; then
      return 0
    fi
  done
  echo 'imac20-hwaccel: unsupported GPU: expected 1002:7340 with subsystem 106b:0219; the bundled patch does not cover 106b:0218.' >&2
  return 1
}
