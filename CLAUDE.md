# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Remote host

This repo is edited locally, but it configures a **remote** machine: the home server `mawile`, reachable at `ssh stalker@mawile`. Any command that needs to observe or affect the running system — `nixos-rebuild`, `systemctl`, `journalctl`, `podman`, checking service/container status or logs, etc. — must be run over SSH on `mawile`, not on the local machine where this checkout lives (they are different machines, and most of these commands don't even exist locally). Only plain file edits to this repo happen locally.

## Commands

**Every build needs `--impure`.** `configuration.nix` imports `private/identity.nix`
by absolute path (see "Private identifiers" below), and pure evaluation refuses to
read absolute paths. Without the flag the build fails with `access to absolute path
'/etc/nixos/private/identity.nix' is forbidden in pure evaluation mode`.

Apply configuration changes (run on `mawile`):
```bash
ssh stalker@mawile sudo nixos-rebuild switch --impure
```

Build without activating (apply on next boot):
```bash
ssh stalker@mawile sudo nixos-rebuild boot --impure
```

Test a build without switching:
```bash
ssh stalker@mawile sudo nixos-rebuild test --impure
```

Format Nix files:
```bash
alejandra .
```

Check the flake for errors without building:
```bash
nix flake check --impure
```

Update flake inputs:
```bash
nix flake update
```

## Architecture

This is a NixOS flake configuration for a single host named **mawile** (`configuration.nix`). The flake uses two nixpkgs channels simultaneously: `nixpkgs` (stable, currently 26.05) and `nixpkgs-unstable`. Unstable packages are accessible anywhere in the config as `pkgs.unstable.<name>` via an overlay defined in `flake.nix`.

**File layout:**
- [flake.nix](flake.nix) — entry point; defines inputs (stable nixpkgs, unstable, home-manager, agenix) and wires them into the single `mawile` host
- [configuration.nix](configuration.nix) — system-level NixOS configuration
- [stalker.nix](stalker.nix) — home-manager config for the `stalker` user (deployed automatically as part of `nixos-rebuild switch`)
- [hardware-configuration.nix](hardware-configuration.nix) — auto-generated hardware scan; don't edit by hand
- [scripts/ytdl.sh](scripts/ytdl.sh) — yt-dlp wrapper inlined into both a system `ytdl` binary and a daily systemd timer
- [secrets/](secrets/) — agenix-encrypted credentials (`*.age`), committed; recipients listed in `secrets/secrets.nix`
- [identity.example.nix](identity.example.nix) — template for the gitignored `private/identity.nix`

**Key services running on this host:**
- **Jellyfin** — media server, proxied via Caddy at `jellyfin.<domain>` with a local TLS cert
- **Navidrome** — music streaming, pointed at the beets-managed library at `/mnt/data/Libraries/Audio/Music/Beets`
- **Radarr / Sonarr** — media acquisition, receive downloads from the seedbox via Syncthing
- **Home Assistant** — smart home; configured entirely in Nix (automations, scripts, adaptive lighting, MQTT switches)
- **Zigbee2MQTT + Mosquitto** — Zigbee device bridge (Sonoff dongle) talking to HA over local MQTT
- **Syncthing** — syncs media from the seedbox and bidirectionally syncs `/mnt/data/Syncthing` with phone/tablet
- **Caddy** — reverse proxy for Jellyfin (and commented-out Calibre)
- **calibre-web-automated** — runs as a Podman OCI container
- **beets** — music library manager; configured in `stalker.nix` with a user-level systemd timer that imports from the Syncthing staging area hourly

**Storage:** Root is ext4 on LUKS. `/mnt/data` is a ZFS dataset (`datapool/encrypted/root`). Sanoid manages ZFS snapshots. ZFS scrub and trim run weekly.

**Boot:** Requires remote unlock over SSH (port 2222 in initrd) using wpa_supplicant to connect wirelessly before decrypting LUKS. `wpa_supplicant.conf` is the one credential still stored as plaintext in `/etc/nixos/secrets/` (gitignored): the initrd consumes it before agenix has run, so it cannot be encrypted like the rest.

## Secrets and private identifiers

Two separate mechanisms, split by *when* the value is needed:

- **Credentials** (`secrets/*.age`) are encrypted with [agenix](https://github.com/ryantm/agenix) and committed. They decrypt to `/run/agenix/<name>` during activation, owned by the consuming service. Edit with `agenix -e <name>.age -i ~/.ssh/<key>` from inside `secrets/`; re-encrypt to a changed recipient list with `agenix --rekey`.
- **Identifiers** (`private/identity.nix`, gitignored) hold the domain, seedbox host and public key, and Syncthing device IDs. These are needed at *evaluation* time — a Caddy virtualHost is an attribute name — and everything Nix evaluates lands in the world-readable store, so encryption cannot help. They are kept out of the repo instead, and imported by absolute path, which is why builds need `--impure`.

There is intentionally no fallback from `private/identity.nix` to `identity.example.nix`: in pure evaluation `builtins.pathExists` returns `false` rather than raising, so a fallback would silently deploy placeholder values and take the host's public services offline. A missing file fails loudly instead.

**Home Assistant config note:** All HA configuration (components, automations, scripts, adaptive lighting, MQTT) lives in `configuration.nix` under `services.home-assistant.config`. The Zigbee device IDs for switches are collected in a `devices` let-binding at the top of that block for reuse across automations.
