#!/usr/bin/env bash
# Builds the autoinstall drive for the Omarchy ISO.
#
# Omarchy's live ISO looks for a volume labelled `cidata` (the cloud-init
# NoCloud label) and, when it carries the files its interactive configurator
# would have written, skips the wizard entirely — see
# /usr/local/bin/omarchy-cidata-load and /root/.automated_script.sh on the ISO.
# So the install here is not a keystroke robot fighting a TUI: it is the
# installer's own supported unattended path, fed the same JSON the wizard
# produces (schema copied from /root/configurator on the 4.0.3 ISO).
#
# The optional `authorized_keys` file is what makes the installed machine
# reachable: the orchestrator's configure_ssh_access phase installs the keys for
# the new user, enables sshd and opens port 22 in the target's ufw.
#
#   tools/vm/cidata.sh            -> $VM_DIR/cidata.iso
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

need xorriso
need openssl
need ssh-keygen

mkdir -p "$VM_DIR"

if [[ ! -f $VM_SSH_KEY ]]; then
	say "generating VM ssh key $VM_SSH_KEY"
	ssh-keygen -t ed25519 -N "" -C "omadungeon-vm" -f "$VM_SSH_KEY" >/dev/null
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The install target. Only one virtio-blk disk is attached (see boot.sh), so the
# guest always names it /dev/vda and the cidata drive can never be mistaken for
# it: that one rides the AHCI bus as a CD-ROM.
disk="/dev/vda"
mib=$((1024 * 1024))
gib=$((mib * 1024))
disk_size=$((VM_DISK_SIZE_GIB * gib))
gpt_backup_reserve=$mib
boot_start=$mib
boot_size=$((2 * gib))
main_start=$((boot_size + boot_start))
main_size=$((disk_size - main_start - gpt_backup_reserve))

password_hash="$(printf '%s' "$VM_PASSWORD" | openssl passwd -6 -stdin)"

cat >"$work/user_credentials.json" <<JSON
{
    "root_enc_password": $(printf '%s' "$password_hash" | jq -Rsa),
    "users": [
        {
            "enc_password": $(printf '%s' "$password_hash" | jq -Rsa),
            "groups": [],
            "sudo": true,
            "username": $(printf '%s' "$VM_USER" | jq -Rsa)
        }
    ]
}
JSON

cat >"$work/user_configuration.json" <<JSON
{
    "app_config": null,
    "archinstall-language": "English",
    "auth_config": {},
    "audio_config": { "audio": "pipewire" },
    "bootloader_config": { "bootloader": "Limine", "uki": false, "removable": false },
    "custom_commands": [],
    "omarchy_install": {
        "mode": "full_disk",
        "defer_provisioning": false,
        "target_mount": "/mnt",
        "boot": {
            "esp_mount": "/boot",
            "esp_path": "/EFI/limine",
            "efi_binary": "limine_x64.efi",
            "enable_fallback": true
        },
        "storage": {
            "kernel": "linux"
        }
    },
    "disk_config": {
        "config_type": "default_layout",
        "device_modifications": [
            {
                "device": "$disk",
                "partitions": [
                    {
                        "btrfs": [],
                        "dev_path": null,
                        "flags": [ "boot", "esp" ],
                        "fs_type": "fat32",
                        "mount_options": [],
                        "mountpoint": "/boot",
                        "obj_id": "ea21d3f2-82bb-49cc-ab5d-6f81ae94e18d",
                        "size": {
                            "sector_size": { "unit": "B", "value": 512 },
                            "unit": "B",
                            "value": $boot_size
                        },
                        "start": {
                            "sector_size": { "unit": "B", "value": 512 },
                            "unit": "B",
                            "value": $boot_start
                        },
                        "status": "create",
                        "type": "primary"
                    },
                    {
                        "btrfs": [
                            { "mountpoint": "/", "name": "@" },
                            { "mountpoint": "/home", "name": "@home" },
                            { "mountpoint": "/var/log", "name": "@log" },
                            { "mountpoint": "/var/cache/pacman/pkg", "name": "@pkg" }
                        ],
                        "dev_path": null,
                        "flags": [],
                        "fs_type": "btrfs",
                        "mount_options": [ "compress=zstd" ],
                        "mountpoint": null,
                        "obj_id": "8c2c2b92-1070-455d-b76a-56263bab24aa",
                        "size": {
                            "sector_size": { "unit": "B", "value": 512 },
                            "unit": "B",
                            "value": $main_size
                        },
                        "start": {
                            "sector_size": { "unit": "B", "value": 512 },
                            "unit": "B",
                            "value": $main_start
                        },
                        "status": "create",
                        "type": "primary"
                    }
                ],
                "wipe": true
            }
        ]
    },
    "hostname": "$VM_HOSTNAME",
    "kernels": [ "linux" ],
    "network_config": { "type": "iso" },
    "ntp": true,
    "parallel_downloads": 8,
    "script": null,
    "services": [],
    "swap": true,
    "timezone": "$VM_TIMEZONE",
    "locale_config": {
        "kb_layout": "$VM_KEYMAP",
        "sys_enc": "UTF-8",
        "sys_lang": "en_US.UTF-8"
    },
    "mirror_config": {
        "custom_repositories": [],
        "custom_servers": [
            {"url": "https://mirror.omarchy.org/\$repo/os/\$arch"},
            {"url": "https://mirror.rackspace.com/archlinux/\$repo/os/\$arch"},
            {"url": "https://geo.mirror.pkgbuild.com/\$repo/os/\$arch"}
        ],
        "mirror_regions": {},
        "optional_repositories": []
    },
    "packages": [
        "base-devel",
        "git",
        "omarchy-keyring",
        "omarchy-settings",
        "omarchy"
    ],
    "profile_config": {
        "gfx_driver": null,
        "greeter": null,
        "profile": {}
    },
    "version": "3.0.9"
}
JSON

printf '%s\n' "$VM_FULL_NAME" >"$work/user_full_name.txt"
printf '%s\n' "$VM_EMAIL" >"$work/user_email_address.txt"
printf '%s\n' "false" >"$work/user_encrypt_installation.txt"
cp "$VM_SSH_KEY.pub" "$work/authorized_keys"

jq -e . "$work/user_configuration.json" >/dev/null || die "generated user_configuration.json is not valid JSON"
jq -e . "$work/user_credentials.json" >/dev/null || die "generated user_credentials.json is not valid JSON"

xorriso -as mkisofs -quiet -V cidata -J -r -o "$VM_CIDATA" "$work"
say "wrote $VM_CIDATA (user=$VM_USER host=$VM_HOSTNAME disk=$disk, ssh key $VM_SSH_KEY.pub)"
