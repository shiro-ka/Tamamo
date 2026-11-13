#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
dnf5 install -y tmux

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

#### Example for enabling a System Unit File

systemctl enable podman.socket

dnf5 remove -y firefox firefox-langpacks
glib-compile-schemas /usr/share/glib-2.0/schemas
systemctl enable tamamo-flatpak-preinstall.service

TAMAMO_VERSION=0
BUILD_DATE=$(date -u +%Y%m%d)
cat > /usr/lib/os-release <<EOF
NAME="Tamamo OS"
VERSION="${TAMAMO_VERSION}.${BUILD_DATE}"
ID=tamamo
ID_LIKE=fedora
VERSION_ID=${TAMAMO_VERSION}
PRETTY_NAME="Tamamo OS ${TAMAMO_VERSION}"
DEFAULT_HOSTNAME="tamamo"
BUILD_ID="${TAMAMO_VERSION}.${BUILD_DATE}${GIT_SHA:+.${GIT_SHA}}"
EOF
sed -i 's|^EFIDIR=.*|EFIDIR="fedora"|' /usr/sbin/grub2-switch-to-blscfg

KERNEL_VERSION=$(dnf5 repoquery --installed --queryformat='%{evr}.%{arch}' kernel)
cp /usr/lib/os-release /tmp/os-release
sed -Ei '/^(VERSION|PRETTY_NAME|BUILD_ID)=/d' /usr/lib/os-release
DRACUT_NO_XATTR=1 dracut --no-hostonly --kver "${KERNEL_VERSION}" --reproducible -f "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"
cp /tmp/os-release /usr/lib/os-release
