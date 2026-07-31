# Template for private/identity.nix.
#
# This file is documentation only — nothing imports it. Copy it to
# private/identity.nix and fill in real values before building:
#
#     cp identity.example.nix private/identity.nix
#
# Why these live outside the repo rather than in secrets/*.age like the real
# credentials do: Nix needs them at *evaluation* time to build the config (a
# Caddy virtualHost is an attribute name, a ddclient zone is a build-time
# string), and everything Nix evaluates ends up in the world-readable Nix
# store. Encryption tools such as agenix decrypt at activation time, which is
# too late to help here. So these are kept out of the repository instead.
#
# configuration.nix imports private/identity.nix by absolute path, which is
# why every rebuild passes --impure. There is deliberately no fallback to this
# file: in pure evaluation `builtins.pathExists` returns false rather than
# raising, so a fallback would silently deploy placeholder values and take the
# host's services offline. A missing file fails loudly instead.
{
  # Base domain. Caddy serves jellyfin.<domain> and navidrome.<domain>, and
  # ddclient keeps its A/AAAA records pointed at this host.
  domain = "example.com";

  # Syncthing device IDs. Not secrets — pairing requires both sides to accept
  # — but they are stable identifiers that follow a device between networks.
  syncthing = {
    seedbox = "AAAAAAA-BBBBBBB-CCCCCCC-DDDDDDD-EEEEEEE-FFFFFFF-GGGGGGG-HHHHHHH";
    pixel = "AAAAAAA-BBBBBBB-CCCCCCC-DDDDDDD-EEEEEEE-FFFFFFF-GGGGGGG-HHHHHHH";

    # A device ID may carry an explicit address, e.g.
    #   "AAAAAAA-...-HHHHHHH at 192.168.1.50:22000"
    tab = "AAAAAAA-BBBBBBB-CCCCCCC-DDDDDDD-EEEEEEE-FFFFFFF-GGGGGGG-HHHHHHH";
  };
}
