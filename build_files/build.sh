#!/bin/bash

set -ouex pipefail

cp -avf "/ctx/system_files"/. /

dnf5 remove -y firefox firefox-langpacks
dnf5 install -y tailscale
rm -f /usr/share/locale/*/LC_MESSAGES/xdg-user-dirs.mo
glib-compile-schemas /usr/share/glib-2.0/schemas
jq '.transports.docker["ghcr.io/shiro-ka"] = [{"type": "sigstoreSigned", "keyPath": "/etc/pki/containers/tamamo.pub", "signedIdentity": {"type": "matchRepository"}}]' /etc/containers/policy.json > /tmp/policy.json
mv /tmp/policy.json /etc/containers/policy.json
systemctl enable tamamo-flatpak-preinstall.service
systemctl enable tailscaled.service

TAMAMO_VERSION=0
FEDORA_VERSION_ID=$(. /usr/lib/os-release && echo "${VERSION_ID}")
BUILD_DATE=$(date -u +%Y%m%d)
cat > /usr/lib/os-release <<EOF
NAME="Tamamo OS"
VERSION="${TAMAMO_VERSION}.${BUILD_DATE}"
ID=tamamo
ID_LIKE=fedora
VERSION_ID=${FEDORA_VERSION_ID}
PRETTY_NAME="Tamamo OS ${TAMAMO_VERSION}"
DEFAULT_HOSTNAME="tamamo"
BUILD_ID="${TAMAMO_VERSION}.${BUILD_DATE}${GIT_SHA:+.${GIT_SHA}}"
EOF
sed -i 's|^EFIDIR=.*|EFIDIR="fedora"|' /usr/sbin/grub2-switch-to-blscfg

if [[ -n "${NVIDIA}" ]]; then
    /ctx/nvidia.sh
fi

KERNEL_VERSION=$(dnf5 repoquery --installed --queryformat='%{evr}.%{arch}' kernel)
cp /usr/lib/os-release /tmp/os-release
sed -Ei '/^(VERSION|PRETTY_NAME|BUILD_ID)=/d' /usr/lib/os-release
DRACUT_NO_XATTR=1 dracut --no-hostonly --kver "${KERNEL_VERSION}" --reproducible --add ostree -f "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"
chmod 0600 "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"
cp /tmp/os-release /usr/lib/os-release
