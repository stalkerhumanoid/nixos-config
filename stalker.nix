{
  config,
  pkgs,
  ...
}: {
  home.stateVersion = "25.05";

  home.username = "stalker";
  home.homeDirectory = "/home/stalker";
  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    settings.user = {
      name = "stalker";
      email = "stalker@fortress.city";
    };
  };

  programs.beets = {
    enable = true;

    # `pkgs.beets` is just `toPythonApplication python3Packages.beets`, with no
    # plugin hook of its own; `pluginOverrides` (the nixpkgs mechanism for
    # enabling external plugins) lives on the underlying python module, so
    # override that and re-wrap it.
    package = pkgs.python3Packages.toPythonApplication (pkgs.python3Packages.beets.override {
      pluginOverrides = {
        # External plugin: copy local sidecar files (cover/booklet images, etc.)
        # alongside the music during import.
        filetote = {
          enable = true;
          propagatedBuildInputs = [pkgs.python3Packages.beets-filetote];
        };
      };
    });

    # Written to ~/.config/beets/config.yaml
    settings = {
      directory = "/mnt/data/Libraries/Audio/Music/Beets";
      library = "/mnt/data/Libraries/Audio/Music/Beets/beets.db";

      # Autotagging (MusicBrainz/AcoustID matching) is disabled below, so beets
      # acts as a pure organizer: it reads the tags already on the files and
      # files them on disk. No matching/tagging plugins here — just file
      # organization, cover/sidecar handling, and replaygain loudness.
      plugins = [
        "fromfilename" # fill sparse tags from the filename when files lack them
        "inline" # define the computed $artistdir field used in the paths below
        "duplicates"
        "fish"
        "edit" # `beet edit` for manual metadata fixes
        "filetote" # copy local cover/booklet images into the library on import
        "fetchart" # download cover art online, but only as a backup (see below)
        "replaygain" # compute EBU R128 loudness-normalization tags on import
        "lyrics" # `beet lyrics` on demand; not run during import (see below)
      ];

      "import" = {
        autotag = false; # no MusicBrainz queries / match prompts — import as-is
        copy = true; # never touch the Syncthing staging copies
        reflink = "auto"; # Use COW reflinks if possible, but fallback to regular copying
        incremental = true; # re-runs only pick up new albums
        duplicate_action = "skip"; # unattended timer must never block on a prompt
      };

      # Track number prefixes every filename (RED 2.3.13) and the leading-zero
      # padding beets applies keeps alphabetical order == play order (2.3.14).
      # Multi-disc releases get one sub-folder per disc ("Disc 1", "Disc 2", ...)
      # so two discs can't collide on track "01", "02", ... in one directory
      # (RED 2.3.15, and 2.3.3's preferred per-disc layout); the `comp` variant
      # is listed first so multi-disc compilations stay under Compilations/
      # instead of falling through to the $albumartist key.
      paths = {
        default = "$albumartist/$album%aunique{}/$track - $title";
        singleton = "$artist/$title";
        comp = "Compilations/$album%aunique{}/$track - $title";
        "comp disctotal:2.." = "Compilations/$album%aunique{}/Disc $disc/$track - $title";
        "disctotal:2.." = "$albumartist/$album%aunique{}/Disc $disc/$track - $title";
      };

      # Loudness normalization: compute EBU R128 ReplayGain tags on import via
      # the ffmpeg backend (works on FLAC and everything else, unlike the
      # MP3/AAC-only `command` backend). Navidrome/Subsonic clients honor these.
      replaygain = {
        auto = true;
        backend = "ffmpeg";
      };

      # Lyrics are fetched only when `beet lyrics` is run by hand. Leaving this
      # off keeps the hourly unattended import from making a web request per
      # track, which is slow and rate-limited.
      lyrics.auto = false;

      # Copy ALL non-music sidecar files that ship alongside the music (cover
      # scans, booklets, rip logs, .cue sheets, .m3u playlists, .nfo, .txt,
      # checksums, even extensionless files, etc.) into the album dir on import,
      # so the Beets library is a complete archival superset of the Syncthing
      # staging dir. Filetote mirrors the import file operation, so it inherits
      # copy/reflink above and never mutates the staging originals. `.*` is
      # filetote's match-all-extensions wildcard (is_allowed_extension()
      # short-circuits true before the extension is even read, so dotless files
      # are caught too); the default path ($albumpath/$old_filename) preserves
      # original filenames.
      filetote.extensions = ".*";

      # fetchart as a *backup* only: download cover art online solely when an
      # album ships with no image of its own. The `filesystem` source runs
      # first and, with cautious=false, counts ANY image already in the album
      # folder as existing art (including odd names like "Cover Scan.jpg" that
      # filetote copied in) — so the online sources are reached only for albums
      # with no local image at all. Downloaded art is saved as cover.jpg, which
      # Navidrome then picks up via CoverArtPriority.
      fetchart = {
        auto = true;
        cautious = false;
        sources = ["filesystem" "coverart" "itunes" "amazon" "albumart"];
        cover_names = ["cover" "front" "folder" "scan" "booklet"];
      };
    };
  };

  systemd.user.services.beets-import = {
    Unit.Description = "Import new music from Syncthing staging into beets library";
    Service = {
      Type = "oneshot";
      # 'beet version' first: deterministically triggers one-time schema/path
      # migrations (e.g. the 2.10.0 portable-library migration) before import.
      ExecStart = [
        "${config.programs.beets.package}/bin/beet version"
        "${config.programs.beets.package}/bin/beet import -q /mnt/data/Libraries/Audio/Music/Downloads"
      ];
    };
  };

  systemd.user.timers.beets-import = {
    Unit.Description = "Hourly beets import from staging";
    Timer = {
      OnCalendar = "hourly";
      Persistent = true;
    };
    Install.WantedBy = ["timers.target"];
  };
}
