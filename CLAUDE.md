# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Remote host

This repo is edited locally, but it configures a **remote** machine: the home server `mawile`, reachable at `ssh stalker@mawile`. Any command that needs to observe or affect the running system — `nixos-rebuild`, `systemctl`, `journalctl`, `podman`, checking service/container status or logs, etc. — must be run over SSH on `mawile`, not on the local machine where this checkout lives (they are different machines, and most of these commands don't even exist locally). Only plain file edits to this repo happen locally.

The local checkout is reached over NFS (`mawile:/` mounted at `/mnt/mawile` on the workstation `ampharos`, `192.168.1.31`). Rebooting the server leaves that mount stale; remount rather than investigating the exports.

**`sudo` on `mawile` requires a password**, so `nixos-rebuild` cannot be run non-interactively over SSH — it fails with `sudo: a terminal is required`. Verify as far as possible without it, then hand the user the exact command to run. `nix build .#nixosConfigurations.mawile.config.system.build.toplevel --impure` builds the entire closure without sudo and catches almost everything; `nix eval --impure` confirms individual option values. Only activation genuinely needs the password.

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
- [README.md](README.md) — front door for readers of the public repo; overlaps this file deliberately
- [LICENSE](LICENSE) — 0BSD

**Key services running on this host:**
- **Jellyfin** — media server, proxied via Caddy at `jellyfin.<domain>` with a local TLS cert
- **Navidrome** — music streaming, pointed at the beets-managed library at `/mnt/data/Libraries/Audio/Music/Beets`
- **Radarr / Sonarr** — media acquisition, receive downloads from the seedbox via Syncthing
- **Home Assistant** — smart home; configured entirely in Nix (automations, scripts, adaptive lighting, MQTT switches)
- **Zigbee2MQTT + Mosquitto** — Zigbee device bridge (Sonoff dongle) talking to HA over local MQTT
- **Syncthing** — syncs media from the seedbox and bidirectionally syncs `/mnt/data/Syncthing` with phone/tablet
- **CouchDB** — remote for Obsidian's Self-hosted LiveSync plugin, proxied via Caddy at `obsidian.<domain>`; database on `/mnt/data/CouchDB` so sanoid snapshots cover it
- **Caddy** — reverse proxy for Jellyfin, Navidrome and CouchDB (and commented-out Calibre), serving a Cloudflare Origin cert
- **calibre-web-automated** — runs as a Podman OCI container
- **beets** — music library manager; configured in `stalker.nix` with a user-level systemd timer that imports from the Syncthing staging area hourly

**Storage:** Root is ext4 on LUKS. `/mnt/data` is a ZFS dataset (`datapool/encrypted/root`). Sanoid manages ZFS snapshots. ZFS scrub and trim run weekly.

**Boot:** Requires remote unlock over SSH (port 2222 in initrd) using wpa_supplicant to connect wirelessly before decrypting LUKS. `wpa_supplicant.conf` is the one credential still stored as plaintext in `/etc/nixos/secrets/` (gitignored): the initrd consumes it before agenix has run, so it cannot be encrypted like the rest.

## This repo is public

Published at <https://github.com/stalkerhumanoid/nixos-config> under 0BSD. Anything committed is world-readable and effectively permanent: GitHub retains unreachable objects after a force-push, so a mistaken commit is **not** undone by rewriting history — it takes deleting and recreating the repository.

Never commit `private/identity.nix`, or anything in `secrets/` that is not `*.age`. `.gitignore` is default-deny inside `secrets/` and covers `/private`, so the only way private material reaches a commit is `git add -f`.

When auditing history, note two traps that produce convincing false "clean" results: `git log -p` omits the root commit's diff unless given `--root`, and the binary `.age` blobs make grep treat a history dump as binary unless given `-a`. Always include a positive control — grep for a string that must be present — or the scan cannot be trusted.

## Secrets and private identifiers

Two separate mechanisms, split by *when* the value is needed:

- **Credentials** (`secrets/*.age`) are encrypted with [agenix](https://github.com/ryantm/agenix) and committed. They decrypt to `/run/agenix/<name>` during activation, mode `0400`, owned by the consuming service. Edit with `agenix -e <name>.age -i ~/.ssh/<key>` from inside `secrets/`; re-encrypt to a changed recipient list with `agenix --rekey`. Three recipients: the mawile host key, the ampharos user key, and an offline age identity held in a password manager.
- **Identifiers** (`private/identity.nix`, gitignored) hold the domain and the Syncthing device IDs. These are needed at *evaluation* time — a Caddy virtualHost is an attribute name — and everything Nix evaluates lands in the world-readable store, so encryption cannot help. They are kept out of the repo instead, and imported by absolute path, which is why builds need `--impure`.

There is intentionally no fallback from `private/identity.nix` to `identity.example.nix`: in pure evaluation `builtins.pathExists` returns `false` rather than raising, so a fallback would silently deploy placeholder values and take the host's public services offline. A missing file fails loudly instead.

## Gotchas that look like bugs

- **NFS port 2049 is deliberately absent from `networking.firewall.allowedTCPPorts`.** It is opened by a source-scoped rule in `networking.firewall.extraCommands`, limited to ampharos. The exports grant rw access to `/`, and NFS `sec=sys` believes whatever UID the client asserts, so that rule is the actual access control. Do not "fix" this by adding 2049 to the port list.
- **`scripts/ytdl.sh` copies its cookie file before use.** yt-dlp opens `--cookies` for writing so it can persist refreshed cookies, but agenix decrypts to `0400`. The temp copy is the fix; do not relax the secret's mode instead.
- **The ZFS pool key is a passphrase file at `/home/stalker/datapool.key`**, on the root disk. raidz2 survives two disk failures but not the loss of that passphrase, and there is no off-device replication of `/mnt/data`.
- **The media services set `openFirewall`**, so Jellyfin, Navidrome, Radarr and Sonarr answer directly on the LAN. The Caddy vhosts are for off-LAN access, not the only door — each app enforces its own login.
- **An agenix `owner` naming a nonexistent user breaks every secret after it.** `agenixChown` runs `chown` over the secrets in order and aborts the whole snippet on the first failure, so a bad `owner` silently leaves later secrets root-owned and the services consuming them unable to start. `services.ddclient` runs with `DynamicUser`, so `owner = "ddclient"` was never valid — that is why `cloudflare.age` has no `owner`. Modules whose `ExecStartPre` is `!`-prefixed (ddclient's is) read their secret as root and copy it in for the dynamic user, so root ownership is correct, not a workaround. When adding a secret, check the consuming module actually declares a static user.
- **CouchDB deliberately does *not* follow that pattern.** It keeps the default `127.0.0.1` bind address and gets no firewall port, because one admin credential guards the whole database — the Caddy vhost is the only door, from the LAN as well as outside it. Do not "fix" this by setting `openFirewall` or adding 5984 to the port list. Its admin password comes from `extraConfigFiles` pointing at an agenix secret rather than `services.couchdb.adminPass`, which would render the password into the world-readable Nix store. Note also that the settings are declared in `extraConfig` instead of running upstream's `/_cluster_setup` POST: that call persists `bind_address = 0.0.0.0` into the writable `/var/lib/couchdb/local.ini`, which is read *last* in the config chain and would silently override `bindAddress`.

**Home Assistant config note:** All HA configuration (components, automations, scripts, adaptive lighting, MQTT) lives in `configuration.nix` under `services.home-assistant.config`. The Zigbee device IDs for switches are collected in a `devices` let-binding at the top of that block for reuse across automations.
