#!/usr/bin/env bash
set -euo pipefail

echo "==> Updating keyring..."
pacman -Sy --noconfirm archlinux-keyring
pacman-key --init
pacman-key --populate archlinux

echo "==> Updating system (including kernel)..."
pacman -Syu --noconfirm linux

echo "==> Base provisioning done. Reboot required."
