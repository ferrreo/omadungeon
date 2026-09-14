# Real-Omarchy VM (tier 3)

Runs the shipped `.deb` inside a genuine Omarchy install under QEMU/KVM, in a
real Hyprland session, and switches the machine's real theme to prove the live
retint against something other than a test fixture.

**Nothing ever appears on the host session.** QEMU runs with `-display none`;
the only display is a VNC server bound to `127.0.0.1` (default 5999), the only
way in is an SSH forward bound to `127.0.0.1:2222`, and the only thing that
reaches out is the QEMU monitor on a unix socket. No `-display gtk/sdl`, no host
Wayland socket passed through. Screenshots come from `grim` *inside* the guest,
or from QEMU's own framebuffer dump, so no window is ever mapped on the host.

## Bring one up

```bash
tools/vm/fetch-iso.sh          # ~6 GB into ~/.cache/omadungeon-vm, sha256-checked
tools/deb.sh full              # dist/omadungeon_<version>_amd64.deb
tools/vm/create.sh --fresh     # install + provision + install the game (~10 min)
tools/vm/verify.sh             # the live-retint proof -> tests/out/vm/
```

## The install is unattended, and not a keystroke robot

The Omarchy ISO looks for a drive labelled `cidata` (cloud-init's NoCloud label).
When it carries the files the interactive configurator would have written —
`user_configuration.json`, `user_credentials.json`, and optionally
`authorized_keys` — `/usr/local/bin/omarchy-cidata-load` copies them into
`/root` and `.automated_script.sh` skips the wizard entirely. `cidata.sh` builds
that drive; the JSON schema is copied from `/root/configurator` on the 4.0.3 ISO.

`authorized_keys` is the important optional one: the installer's
`configure_ssh_access` phase installs the key for the new user, enables `sshd`
and opens port 22 in the target's ufw, which is what makes the finished machine
reachable at all (a stock Omarchy ships sshd disabled behind a default-deny
firewall).

| Script | Purpose |
|--------|---------|
| `common.sh` | Shared settings, `vm_ssh` / `vm_sudo` / `vm_desktop` helpers. Sourced, not run. |
| `fetch-iso.sh` | Downloads and sha256-verifies `omarchy-<ver>.iso` into `~/.cache/omadungeon-vm`. |
| `cidata.sh` | Generates the VM ssh key and builds the `cidata` autoinstall drive. |
| `boot.sh install\|run` | Starts QEMU. `install` attaches the ISO + cidata; `run` boots the installed disk alone. |
| `create.sh [--fresh]` | The whole bring-up: cidata → install → reboot → provision → install the game. |
| `wait-ssh.sh` | Blocks until the guest's sshd answers. |
| `provision.sh` | Headless-QA setup in the guest: SDDM autologin, fixed 1920×1080 mode. |
| `install-game.sh` | Unpacks the `.deb`'s payload onto the machine (Arch has no dpkg; `bsdtar` reads a .deb). |
| `game.sh start\|key\|hold\|status\|env\|log\|stop` | Drives the game in the guest's Hyprland (`wtype` for input). |
| `run.sh <scenario>` | Runs one `--test-scenario` inside the guest and copies its screenshot back. |
| `shot.sh <name>` | `grim` inside the guest → `tests/out/vm/<name>.png`. |
| `console-shot.sh [name]` | QEMU framebuffer dump — works before the guest has networking or a desktop. |
| `theme.sh list\|set\|bg-next\|state` | Drives the guest's real `omarchy-theme-*` commands. |
| `fullscreen.sh state\|bind\|current\|prove` | Owner report 12: a Hyprland fullscreen made behind the game's back, and the game's own Video row following it. Checks the installed binary against the `.deb` and the two PNGs against each other before it believes itself. |
| `verify.sh [themes...]` | The live-retint proof: switch themes, change the wallpaper, check the pid never moved. |
| `ssh.sh` / `stop.sh` | Shell in, and shut down. |

## Host requirements

`qemu-system-x86_64` (with `/dev/kvm` readable — be in the `kvm` group),
`qemu-img`, `xorriso`, `socat`, `ImageMagick` (`magick`), `jq`, `openssl`,
`ssh`/`scp`, and OVMF firmware at `/usr/share/OVMF/OVMF_CODE_4M.fd`. No libvirt,
no `virsh`, no `default` network: plain QEMU with user-mode networking.

## Guest credentials

User `omadungeon`, password `omadungeon`, hostname `omadungeon-vm`, key at
`~/.cache/omadungeon-vm/id_ed25519`. This is a throwaway QA machine reachable
only from loopback; do not reuse any of it anywhere else.
