#!/bin/bash

set -ouex pipefail

IMAGE_NAME=silverblue AKMODNV_PATH=/tmp/akmods/rpms MULTILIB=0 /tmp/akmods/rpms/ublue-os/nvidia-install.sh
rm -f /usr/share/vulkan/icd.d/nouveau_icd.*.json
ln -sf libnvidia-ml.so.1 /usr/lib64/libnvidia-ml.so
cat > /usr/lib/bootc/kargs.d/00-nvidia.toml <<KARGS
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1", "initcall_blacklist=simpledrm_platform_driver_init"]
KARGS
