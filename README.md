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
sudo nixos-rebuild switch
```

Evaluation is pure — no `--impure`. Nothing here is read from outside the
flake while Nix is evaluating, and the section below is what makes that
possible for the one value that wants to be.

## Secrets

Credentials live in `secrets/*.age`, encrypted with
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

Two things about agenix that cost me time. Renaming a secret needs no
re-encryption at all — the filename isn't bound into the ciphertext, so
`git mv` plus a `secrets.nix` edit is the whole job. And `agenix -e` silently
overrides `$EDITOR` to `cp -- /dev/stdin` whenever stdin isn't a TTY, so
writing one non-interactively means piping the plaintext in
(`agenix -e foo.age < plaintext`); setting `EDITOR` gets you an *empty* secret
that decrypts perfectly happily. Check the byte count.

## Keeping the domain out of the Nix store

The interesting problem. My base domain is in `secrets/domain.age`, but its
two consumers would normally want it while Nix is *evaluating* — a Caddy
virtualHost is an attribute name, a ddclient zone is a build-time string — and
everything Nix evaluates lands in the world-readable store. agenix decrypts at
activation, far too late to help. This is what the config used to reach for an
absolute-path import and `--impure` to solve.

The fix is to let both services learn it at runtime instead:

- **Caddy** takes `domain.age` as its `environmentFile`. The secret is a
  single `DOMAIN=<domain>` line so systemd reads it verbatim, and the vhosts
  are named `jellyfin.{$DOMAIN}`, `navidrome.{$DOMAIN}`, `obsidian.{$DOMAIN}`.
  The Caddyfile adapter expands `{$VAR}` when it loads the config. The NixOS
  module's only build-time step over the Caddyfile is `caddy fmt`, which leaves
  the placeholder alone — there's no build-time `caddy validate` to trip over
  it. Unset the variable and the site address becomes `jellyfin.`, which Caddy
  rejects outright; the failure is loud, not silent.
- **ddclient** gets `zone = "@domain@"` and a matching `domains` entry,
  substituted by an extra `ExecStartPre` that sources the same secret and
  `sed`s the config in `/run`. It has to be `lib.mkAfter`, since the module's
  own prestart is what puts the file there, and `!`-prefixed so it runs as root
  and can read the `0400` secret.

`domain.age` has no `owner` for the same reason `cloudflare.age` doesn't:
systemd reads `EnvironmentFile` as PID 1 before dropping privileges, and the
ddclient hook is root.

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
  reach the network to unlock the disk at all. `boot.initrd.secrets` points at
  it by absolute path and pure evaluation is fine with that — the module only
  `toString`s the value into `append-initrd-secrets`, never reading or copying
  it, which is also what keeps the plaintext out of the store. Only `import` or
  `readFile` of an absolute path trips pure eval.
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

`pkgs.unstable.<name>` is available anywhere, via an overlay in `flake.nix`.
