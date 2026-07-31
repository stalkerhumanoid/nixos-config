# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{
  config,
  pkgs,
  ...
}: let
  # Private, eval-time identifiers: domain, seedbox, Syncthing device IDs.
  # Kept out of the repo rather than encrypted, because Nix needs them while
  # building and everything it evaluates lands in the world-readable store.
  # Imported by absolute path, so rebuilds require --impure; see
  # identity.example.nix for the shape. Deliberately no pathExists fallback —
  # in pure eval that returns false rather than raising, which would silently
  # deploy placeholder values instead of failing.
  identity = import /etc/nixos/private/identity.nix;

  # Single source of truth for the ytdl script, used both as a CLI tool
  # and by the systemd timer/service below.
  ytdlScript = pkgs.writeShellScriptBin "ytdl" (builtins.readFile ./scripts/ytdl.sh);
in {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    download-buffer-size = 524288000;
    auto-optimise-store = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 20;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.luks.devices."luks-65933b9c-da15-4fe4-8f26-c1a244fe08cc".device = "/dev/disk/by-uuid/65933b9c-da15-4fe4-8f26-c1a244fe08cc";

  boot.initrd = {
    availableKernelModules = [
      "mt7921u"
      "ccm"
      "ctr"
    ];
    systemd = {
      enable = true;
      packages = [pkgs.wpa_supplicant];
      initrdBin = [pkgs.wpa_supplicant];
      targets.initrd.wants = ["wpa_supplicant@wlp0s20f0u5.service"];
      services."wpa_supplicant@".unitConfig.DefaultDependencies = false;
      users.root.shell = "/bin/systemd-tty-ask-password-agent";
      network.enable = true;
      network.networks."Urth" = {
        matchConfig.Name = "wlp0s20f0u5";
        networkConfig.DHCP = "yes";
      };
      settings.Manager = {
        DefaultDeviceTimeoutSec = 300;
      };
    };
    secrets."/etc/wpa_supplicant/wpa_supplicant-wlp0s20f0u5.conf" =
      /etc/nixos/secrets/wpa_supplicant.conf;
    network = {
      enable = true;
      ssh = {
        enable = true;
        port = 2222;
        hostKeys = ["/etc/ssh/initrd/ssh_host_ed25519_key"];
        authorizedKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG1WILjLj/0pack7Ga0i2JErAjgobm1Frc99BAE9TED7 stalker@ampharos"
        ];
      };
    };
  };

  boot.supportedFilesystems = ["zfs"];
  boot.zfs.requestEncryptionCredentials = ["datapool/encrypted"];
  boot.zfs.forceImportRoot = true;

  networking.hostName = "mawile";
  networking.hostId = "50a5ec6f";
  networking.networkmanager.enable = true;

  time.timeZone = "America/New_York";

  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Headless server: no X11, no desktop. This only sets the console keymap.
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver # previously vaapiIntel
      libva-vdpau-driver
      # intel-compute-runtime # OpenCL filter support (hardware tonemapping and subtitle burn-in), 12th gen or newer
      intel-compute-runtime-legacy1 # tonemapping up to 12th gen
      # vpl-gpu-rt # QSV on 11th gen or newer
      # intel-media-sdk # DEPRECATED, QSV up to 11th gen
    ];
  };

  programs.fish.enable = true;

  # Stop slow man cache generation
  # https://discourse.nixos.org/t/slow-build-at-building-man-cache/52365/3
  documentation.man.cache.enable = false;

  services.logrotate.enable = true;

  users.users.stalker = {
    isNormalUser = true;
    description = "Artie Yamamoto";
    linger = true;
    extraGroups = [
      "wheel"
      "docker"
      "fuse"
      "libvirtd"
      "render"
    ];
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG1WILjLj/0pack7Ga0i2JErAjgobm1Frc99BAE9TED7 stalker@ampharos"
    ];
    packages = with pkgs; [
      ghostty
      pciutils
      usbutils
      speedtest-cli
      claude-code
      micro
    ];
  };

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    nixd
    alejandra
    ytdlScript
    yt-dlp
    jq
  ];

  systemd.timers."ytdl" = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      Unit = "ytdl.service";
    };
  };

  systemd.services."ytdl" = {
    serviceConfig = {
      Type = "oneshot";
      User = "stalker";
      ExecStart = "${ytdlScript}/bin/ytdl";
    };
    path = with pkgs; [
      yt-dlp
      jq
    ];
  };

  services.zfs = {
    autoScrub = {
      enable = true;
      interval = "Sat 05:00";
    };
    trim = {
      enable = true;
      interval = "Sat 05:00";
    };
  };

  services.sanoid = {
    enable = true;
    datasets = {
      "datapool" = {
        use_template = ["production"];
        recursive = "zfs";
      };
    };
    templates = {
      "production" = {
        hourly = 36;
        daily = 30;
        monthly = 3;
        yearly = 0;
        autosnap = true;
        autoprune = true;
      };
    };
  };

  services.fwupd.enable = true;

  services.nfs = {
    server = {
      enable = true;
      # Exported only to ampharos. NFS `sec=sys` believes whatever UID the
      # client asserts, so the rule scoping 2049 to that address in
      # networking.firewall.extraCommands below is load-bearing rather than
      # defence in depth. /home is not exported separately: it sits on the root
      # filesystem already covered by the / export.
      exports = ''
        / 192.168.1.31(rw,no_subtree_check,root_squash)
        /mnt/data 192.168.1.31(rw,no_subtree_check,root_squash)
      '';
    };
    settings = {
      nfsd.udp = false;
      nfsd.vers3 = false;
      nfsd.vers4 = true;
      nfsd."vers4.0" = false;
      nfsd."vers4.1" = false;
      nfsd."vers4.2" = true;
    };
  };

  # Secrets live in this repo encrypted (secrets/*.age, recipients listed in
  # secrets/secrets.nix) and are decrypted to /run/agenix during activation.
  # wpa_supplicant.conf is deliberately not here: the initrd consumes it before
  # agenix has run, so it stays plaintext and gitignored.
  age.secrets = {
    cloudflare = {
      file = ./secrets/cloudflare.age;
      owner = "ddclient";
    };
    stalkersystems-key = {
      file = ./secrets/stalkersystems-key.age;
      owner = "caddy";
    };
    stalkersystems-pem = {
      file = ./secrets/stalkersystems-pem.age;
      owner = "caddy";
    };
    syncthing-password = {
      file = ./secrets/syncthing-password.age;
      owner = "stalker";
    };
    youtube-cookies = {
      file = ./secrets/youtube-cookies.age;
      owner = "stalker";
    };
  };

  services.ddclient = {
    verbose = true;
    enable = true;
    protocol = "cloudflare";
    ssl = true;
    passwordFile = config.age.secrets.cloudflare.path;
    zone = identity.domain;
    domains = [identity.domain];
  };

  services.caddy = {
    enable = true;
    virtualHosts = {
      "jellyfin.${identity.domain}".extraConfig = ''
        tls ${config.age.secrets.stalkersystems-pem.path} ${config.age.secrets.stalkersystems-key.path}
        reverse_proxy localhost:8096
      '';
      "navidrome.${identity.domain}".extraConfig = ''
        tls ${config.age.secrets.stalkersystems-pem.path} ${config.age.secrets.stalkersystems-key.path}
        reverse_proxy localhost:4533
      '';
      # "calibre.${identity.domain}".extraConfig = ''
      #   tls ${config.age.secrets.stalkersystems-pem.path} ${config.age.secrets.stalkersystems-key.path}
      #   reverse_proxy localhost:8083
      # '';
    };
  };

  # Home Assistant
  services.home-assistant = let
    devices = {
      switches = {
        entryway = "4d943dc3edbc73b784e224f99579ebe3";
        left_nightstand = "84beeff6b59c8fccb61760191c7a20a4";
        right_nightstand = "a1ffd080905e05cd1850c54eac317c05";
      };
    };
  in {
    package = pkgs.home-assistant;
    enable = true;
    extraComponents = [
      # Components required to complete the onboarding
      "analytics"
      "google_translate"
      "met"
      "radio_browser"
      "shopping_list"
      # Recommended for fast zlib compression
      # https://www.home-assistant.io/integrations/isal
      "isal"
      # My additions
      "default_config" # https://www.home-assistant.io/integrations/default_config/
      "mqtt"
      "airgradient"
      "mobile_app"
    ];
    customComponents = [
      pkgs.home-assistant-custom-components.adaptive_lighting
    ];
    config = {
      adaptive_lighting = {
        name = "Adaptive Lighting";
        lights = [
          "light.bedroom_shelf_lamp"
          "light.left_nightstand_lamp"
          "light.right_nightstand_lamp"
          "light.living_room_floor_lamp"
        ];
        prefer_rgb_color = false;
        transition = 45;
        initial_transition = 1;
        interval = 90;
        min_brightness = 40;
        max_brightness = 100;
        min_color_temp = 2000;
        max_color_temp = 6600;
        sleep_brightness = 1;
        sleep_color_temp = 1000;
        sunrise_time = "07:00:00";
        min_sunset_time = "07:00:00";
        take_over_control = true;
        detect_non_ha_changes = false;
        only_once = false;
      };
      mobile_app = {};
      light = {
        platform = "group";
        name = "All Lights";
        entities = [
          "light.bedroom_shelf_lamp"
          "light.left_nightstand_lamp"
          "light.right_nightstand_lamp"
          "light.living_room_floor_lamp"
        ];
      };
      script = {
        toggle_all_lights = {
          sequence = [
            {
              "if" = [
                {
                  condition = "or";
                  conditions = [
                    {
                      condition = "state";
                      entity_id = "light.bedroom_shelf_lamp";
                      state = "off";
                    }
                    {
                      condition = "state";
                      entity_id = "light.left_nightstand_lamp";
                      state = "off";
                    }
                    {
                      condition = "state";
                      entity_id = "light.right_nightstand_lamp";
                      state = "off";
                    }
                    {
                      condition = "state";
                      entity_id = "light.living_room_floor_lamp";
                      state = "off";
                    }
                    {
                      condition = "state";
                      entity_id = "switch.living_room_smart_plug";
                      state = "off";
                    }
                  ];
                }
              ];
              "then" = [
                {
                  action = "light.turn_on";
                  target = {
                    area_id = [
                      "bedroom"
                      "living_room"
                    ];
                  };
                }
                {
                  action = "switch.turn_on";
                  target = {
                    entity_id = "switch.living_room_smart_plug";
                  };
                }
              ];
              "else" = [
                {
                  action = "switch.turn_off";
                  target = {
                    entity_id = "switch.living_room_smart_plug";
                  };
                }
                {
                  action = "light.turn_off";
                  target = {
                    area_id = [
                      "bedroom"
                      "living_room"
                    ];
                  };
                }
              ];
            }
          ];
        };
        toggle_living_room_lights = {
          sequence = [
            {
              "if" = [
                {
                  condition = "or";
                  conditions = [
                    {
                      condition = "state";
                      entity_id = "light.living_room_floor_lamp";
                      state = "off";
                    }
                    {
                      condition = "state";
                      entity_id = "switch.living_room_smart_plug";
                      state = "off";
                    }
                  ];
                }
              ];
              "then" = [
                {
                  action = "light.turn_on";
                  target = {
                    entity_id = "light.living_room_floor_lamp";
                  };
                }
                {
                  action = "switch.turn_on";
                  target = {
                    entity_id = "switch.living_room_smart_plug";
                  };
                }
              ];
              "else" = [
                {
                  action = "switch.turn_off";
                  target = {
                    entity_id = "switch.living_room_smart_plug";
                  };
                }
                {
                  action = "light.turn_off";
                  target = {
                    entity_id = "light.living_room_floor_lamp";
                  };
                }
              ];
            }
          ];
        };
      };
      automation = [
        {
          alias = "Toggle All Lights";
          mode = "single";
          triggers = [
            {
              domain = "mqtt";
              device_id = devices.switches.entryway;
              type = "action";
              subtype = "single";
              trigger = "device";
            }
          ];
          actions = [
            {
              action = "script.toggle_all_lights";
            }
          ];
        }
        {
          alias = "Toggle Left Nightstand Lamp";
          mode = "single";
          triggers = [
            {
              domain = "mqtt";
              device_id = devices.switches.left_nightstand;
              type = "action";
              subtype = "single";
              trigger = "device";
            }
          ];
          actions = [
            {
              action = "light.toggle";
              target = {
                entity_id = "light.left_nightstand_lamp";
              };
            }
          ];
        }
        {
          alias = "Toggle Right Nightstand Lamp";
          mode = "single";
          triggers = [
            {
              domain = "mqtt";
              device_id = devices.switches.right_nightstand;
              type = "action";
              subtype = "single";
              trigger = "device";
            }
          ];
          actions = [
            {
              action = "light.toggle";
              target = {
                entity_id = "light.right_nightstand_lamp";
              };
            }
          ];
        }
        {
          alias = "Toggle All Bedroom Lights";
          mode = "single";
          triggers = [
            {
              domain = "mqtt";
              device_id = devices.switches.left_nightstand;
              type = "action";
              subtype = "double";
              trigger = "device";
            }
            {
              domain = "mqtt";
              device_id = devices.switches.right_nightstand;
              type = "action";
              subtype = "double";
              trigger = "device";
            }
          ];
          actions = [
            {
              action = "light.toggle";
              target = {
                area_id = "bedroom";
              };
            }
          ];
        }
        {
          alias = "Toggle Living Room Lights";
          mode = "single";
          triggers = [
            {
              domain = "mqtt";
              device_id = devices.switches.entryway;
              type = "action";
              subtype = "double";
              trigger = "device";
            }
          ];
          actions = [
            {
              action = "script.toggle_living_room_lights";
            }
          ];
        }
        {
          alias = "Left Nightstand Only";
          mode = "single";
          triggers = [
            {
              domain = "mqtt";
              device_id = devices.switches.left_nightstand;
              type = "action";
              subtype = "hold";
              trigger = "device";
            }
          ];
          actions = [
            {
              action = "light.turn_off";
              target = {
                entity_id = [
                  "light.bedroom_shelf_lamp"
                  "light.right_nightstand_lamp"
                ];
              };
            }
            {
              action = "light.turn_on";
              target = {
                entity_id = "light.left_nightstand_lamp";
              };
            }
          ];
        }
        {
          alias = "Right Nightstand Only";
          mode = "single";
          triggers = [
            {
              domain = "mqtt";
              device_id = devices.switches.right_nightstand;
              type = "action";
              subtype = "hold";
              trigger = "device";
            }
          ];
          actions = [
            {
              action = "light.turn_off";
              target = {
                entity_id = [
                  "light.bedroom_shelf_lamp"
                  "light.left_nightstand_lamp"
                ];
              };
            }
            {
              action = "light.turn_on";
              target = {
                entity_id = "light.right_nightstand_lamp";
              };
            }
          ];
        }
      ];
    };
  };

  services.mosquitto = {
    enable = true;
    listeners = [
      {
        # Anonymous read/write on every topic is only acceptable because this
        # listener is bound to loopback: the sole clients are Zigbee2MQTT and
        # Home Assistant, both running on this host. Exposing this off-box
        # would hand anyone on the network full control of the Zigbee devices.
        acl = ["pattern readwrite #"];
        omitPasswordAuth = true;
        settings.allow_anonymous = true;
        address = "127.0.0.1";
        port = 1883;
      }
    ];
  };

  services.zigbee2mqtt = {
    enable = true;
    settings = {
      homeassistant = {
        enabled = config.services.home-assistant.enable;
        experimental_event_entities = true;
        legacy_action_sensor = false;
      };
      frontend = {
        enabled = true;
        port = 49507;
      };
      permit_join = false;
      serial = {
        port = "/dev/serial/by-id/usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_7a2293ed9a44ed119d5bcec90a86e0b4-if00-port0";
        adapter = "zstack";
      };
      mqtt = {
        server = "mqtt://localhost:1883";
        base_topic = "zigbee2mqtt";
      };
    };
  };

  virtualisation.podman.enable = true;

  systemd.tmpfiles.rules = [
    "d /var/lib/calibre-web-automated 0755 1000 100 -"
    "d /mnt/data/Libraries/Books/Calibre 0755 1000 100 -"
    "d /mnt/data/Libraries/Books/Ingest 0755 1000 100 -"
  ];

  virtualisation.oci-containers.containers.calibre-web-automated = {
    image = "crocodilestick/calibre-web-automated:latest";
    ports = ["8083:8083"];
    environment = {
      PUID = "1000";
      PGID = "100";
      TZ = "America/New_York";
    };
    volumes = [
      "/var/lib/calibre-web-automated:/config"
      "/mnt/data/Libraries/Books/Calibre:/calibre-library"
      "/mnt/data/Libraries/Books/Ingest:/cwa-book-ingest"
    ];
  };

  # Media Services
  #
  # These all set openFirewall, so they answer directly on the LAN as well as
  # through the Caddy vhosts above. The TLS proxy is therefore a convenience
  # for off-LAN access, not the only door — each app enforces its own login.
  services.jellyfin = {
    enable = true;
    openFirewall = true;
    user = "stalker";
  };

  services.navidrome = {
    enable = true;
    openFirewall = true;
    user = "stalker";
    settings = {
      # https://www.navidrome.org/docs/usage/configuration-options/#available-options
      Scanner.Schedule = "@every 1h";
      TranscodingCacheSize = "500MB";
      MusicFolder = "/mnt/data/Libraries/Audio/Music/Beets";
      Address = "0.0.0.0";
      Port = 4533;
      EnableSharing = true;
      CoverJpegQuality = 95;
      AutoImportPlaylists = false;
      # Recognize cover art saved under uncommon names (e.g. "Cover Scan.jpg",
      # obi/booklet scans copied in by beets' filetote plugin). Comma-separated,
      # case-insensitive glob patterns, highest priority first: prefer files
      # whose name contains cover/front, then fall back to any image, then to
      # embedded art.
      CoverArtPriority = "cover.*, folder.*, front.*, *cover*, *front*, *.jpg, *.jpeg, *.png, *.webp, embedded";
    };
  };

  services.radarr = {
    enable = true;
    openFirewall = true;
    user = "stalker";
  };

  services.sonarr = {
    enable = true;
    openFirewall = true;
    user = "stalker";
  };

  services.syncthing = {
    enable = true;
    openDefaultPorts = true;
    user = "stalker";
    configDir = "/home/stalker/.config/syncthing";
    guiAddress = "0.0.0.0:8384";
    guiPasswordFile = config.age.secrets.syncthing-password.path;

    settings = {
      gui = {
        user = "stalker";
      };

      options = {
        # Limit bandwidth if needed (0 = unlimited, value in KiB/s)
        maxRecvKbps = 0;
        maxSendKbps = 0;
        # Don't phone home
        urAccepted = -1;
      };

      devices = {
        "Seedbox" = {
          id = identity.syncthing.seedbox;
        };

        "Pixel 10a" = {
          id = identity.syncthing.pixel;
        };

        "Tab A9+" = {
          id = identity.syncthing.tab;
        };
      };

      folders = {
        "Radarr-Movies" = {
          id = "dcz6h-huwdd";
          path = "/mnt/data/Libraries/Videos/Movies/Seedbox";
          devices = ["Seedbox"];
          type = "receiveonly";
          ignorePerms = true;
        };

        "Sonarr-Shows" = {
          id = "bbw7g-ivaa4";
          path = "/mnt/data/Libraries/Videos/Shows/Seedbox";
          devices = ["Seedbox"];
          type = "receiveonly";
          ignorePerms = true;
        };

        "Music-Downloads" = {
          id = "o7zzg-pdwt7";
          path = "/mnt/data/Libraries/Audio/Music/Downloads";
          devices = ["Seedbox"];
          type = "receiveonly";
          ignorePerms = true;
        };

        "Syncthing" = {
          id = "ord1s-yh35z";
          path = "/mnt/data/Syncthing";
          devices = [
            "Pixel 10a"
            "Tab A9+"
          ];
          type = "sendreceive";
          ignorePerms = true;
        };
      };
    };
  };

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [
    80 # HTTP
    443 # HTTPS
    8083 # calibre-web-automated
    8384 # Syncthing frontend
    49507 # zigbee2mqtt frontend
    config.services.home-assistant.config.http.server_port
  ];
  networking.firewall.allowedUDPPorts = [
    443 # HTTPS (Caddy QUIC/HTTP3)
  ];

  # NFS is deliberately absent from allowedTCPPorts above: the exports grant rw
  # access to /, so 2049 must be reachable from ampharos only, never from the
  # rest of the LAN.
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -p tcp -s 192.168.1.31 --dport 2049 -j nixos-fw-accept
  '';
  networking.firewall.extraStopCommands = ''
    iptables -D nixos-fw -p tcp -s 192.168.1.31 --dport 2049 -j nixos-fw-accept || true
  '';
  networking.firewall.allowPing = true;
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
