# Recipient list for agenix. Read only by the `agenix` CLI when encrypting or
# rekeying — it is not part of the NixOS evaluation.
#
# Every secret is encrypted to three keys so that no single loss locks us out:
#   mawile   — the host key, so the machine decrypts unattended at activation
#   ampharos — the workstation key, for `agenix -e` without reaching for backups
#   recovery — an offline age identity kept in a password manager, so that a
#              dead mawile does not take the only decryption path with it
#
# After adding or removing a recipient here, run `agenix --rekey` so existing
# secrets are re-encrypted to the new set.
let
  mawile = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINNomWGu38cSi4LLzMEwCzUIrdsoF7+1b+ZcEk/1ha7/";
  ampharos = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG1WILjLj/0pack7Ga0i2JErAjgobm1Frc99BAE9TED7";
  recovery = "age1cux5c08ac4fzyj2zzw7ggxvgmtsvqe8plyhh6q8xkz2eey60edqqkvt0ah";

  all = [mawile ampharos recovery];
in {
  "cloudflare.age".publicKeys = all;
  "couchdb-admin.age".publicKeys = all;
  "stalkersystems-key.age".publicKeys = all;
  "stalkersystems-pem.age".publicKeys = all;
  "syncthing-password.age".publicKeys = all;
  "youtube-cookies.age".publicKeys = all;
}
