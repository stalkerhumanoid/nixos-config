# mawile

This is my NixOS configuration for my home server, "Mawile".
Some things I run here:
- Media library management and streaming (Jellyfin, Navidrome,
Radarr, Sonarr, Calibre)
- Home automation (Home Assistant, Zigbee2MQTT,
Mosquitto)
- File sync (Syncthing)
- Notes sync (CouchDB, as the remote for Obsidian's Self-hosted LiveSync)
- WAN access (Caddy reverse proxy)

I use ZFS for the entire machine. There is an encrypted root that unlocks remotely over SSH.
Everything is one flake for one host.
It's licensed 0BSD, so take anything you want.

Everything below this was written by Claude to help describe some of the quirks of my setup so I'm not scratching my head in the future.

## Applying changes

```bash
sudo nixos-rebuild switch --impure
```

**`--impure` is not optional.** `configuration.nix` imports
`private/identity.nix` by absolute path, and pure evaluation refuses to read
absolute paths. Without the flag you get:

```
error: access to absolute path '/etc/nixos/private/identity.nix' is
forbidden in pure evaluation mode
```

That failure is deliberate. There is no `pathExists` fallback to
`identity.example.nix`, because in pure evaluation `builtins.pathExists`
returns `false` rather than raising — a fallback would silently build with
placeholder values and take Caddy and ddclient offline instead of failing.

## Secrets: two mechanisms, split by timing

The split is the one genuinely non-obvious thing about this repo.

**Credentials** live in `secrets/*.age`, encrypted with
[agenix](https://github.com/ryantm/agenix) and committed. They decrypt to
`/run/agenix/<name>` at activation, mode `0400`, owned by the consuming
service. Each is encrypted to three recipients (`secrets/secrets.nix`): the
host key so the machine decrypts unattended, a workstation key for editing,
and an offline age identity kept in a password manager — encrypting to the
host key alone would mean a dead host takes the only decryption path with it.

```bash
cd secrets
agenix -e cloudflare.age -i ~/.ssh/<key>   # edit
agenix --rekey                             # after changing recipients
```

**Identifiers** — domain, Syncthing device IDs — live in
`private/identity.nix`, gitignored. These *cannot* be encrypted: Nix needs
them while evaluating (a Caddy virtualHost is an attribute name), and
everything Nix evaluates lands in the world-readable store. Encryption tools
decrypt at activation, which is too late. So they're kept out of the repo
instead. Copy `identity.example.nix` to `private/identity.nix` to adapt this.

## Boot

The root filesystem is LUKS-encrypted, and the machine is on wireless, so
unattended boot isn't possible. The initrd brings up wpa_supplicant, gets
DHCP, and starts sshd on **port 2222**:

```bash
ssh -p 2222 root@mawile   # drops straight into the passphrase prompt
```

After switch-root, `zfs-import-datapool.service` unlocks the pool using the
key at `/home/stalker/datapool.key`.

## Gotchas

- **The ZFS pool key lives on the root disk** (`/home/stalker/datapool.key`).
  raidz2 survives two disk failures; it does nothing if that passphrase is
  lost. Keep a copy off this machine.
- **`wpa_supplicant.conf` is the one plaintext secret** (gitignored, not
  agenix). The initrd consumes it before agenix has run, and it's needed to
  reach the network to unlock the disk at all.
- **NFS port 2049 is not in `allowedTCPPorts`.** It's opened by an explicit
  source-scoped rule in `networking.firewall.extraCommands`, because the
  exports grant rw access to `/` and NFS `sec=sys` trusts whatever UID the
  client asserts. Widening that rule widens root access to the whole disk.
- **yt-dlp gets a *copy* of its cookie file.** It opens `--cookies` for
  writing to persist refreshed cookies, but agenix decrypts to `0400`, so
  `scripts/ytdl.sh` copies to a temp file first. Refreshed cookies are
  discarded; re-export from the browser and `agenix -e` when they expire.
- **The media apps set `openFirewall`**, so they answer directly on the LAN.
  The Caddy vhosts are convenience for off-LAN access, not the only door.
- **An agenix `owner` pointing at a user that doesn't exist breaks the
  secrets after it.** The chown step walks the secrets in order and aborts the
  whole snippet on the first failure, leaving later ones root-owned. `ddclient`
  runs under `DynamicUser`, so `cloudflare.age` correctly has no `owner` — its
  `!`-prefixed prestart reads it as root and copies it in.
- **CouchDB is the exception to that.** It stays on `127.0.0.1` with no
  firewall port, because a single admin credential guards the whole database
  and the Caddy vhost is the only door — on the LAN too. Its password comes
  from
  `extraConfigFiles` reading an agenix secret — `services.couchdb.adminPass`
  would put it in the world-readable Nix store. The LiveSync settings are
  declared in `extraConfig` rather than by running upstream's `/_cluster_setup`
  POST, which persists `bind_address = 0.0.0.0` into the writable
  `/var/lib/couchdb/local.ini`; that file is read last and would quietly
  override `bindAddress`.
- **This repo is edited over NFS** from the workstation at `/mnt/mawile`, so a
  server reboot leaves the mount stale. Remount rather than debugging exports.

## Layout

| Path | |
|---|---|
| `flake.nix` | inputs (nixpkgs stable + unstable, home-manager, agenix), single `mawile` host |
| `configuration.nix` | everything system-level, including all Home Assistant config |
| `stalker.nix` | home-manager: beets library manager and its hourly import timer |
| `hardware-configuration.nix` | generated; don't hand-edit |
| `scripts/ytdl.sh` | yt-dlp wrapper, inlined as both a CLI tool and a daily timer |
| `secrets/` | agenix ciphertext + recipient list |
| `identity.example.nix` | template for the gitignored `private/identity.nix` |

`pkgs.unstable.<name>` is available anywhere, via an overlay in `flake.nix`.
