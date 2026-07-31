{
  description = "Stalker Humanoid's Nix Config";

  inputs = {
    # master.url = "github:nixos/nixpkgs/master";
    # nur.url = github:nix-community/nur;

    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    nixpkgs-unstable,
    home-manager,
    agenix,
    ...
  }: let
    system = "x86_64-linux";
    overlay-unstable = final: prev: {
      unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
        config.permittedInsecurePackages = [];
      };
    };
  in {
    nixosConfigurations = {
      mawile =
        nixpkgs.lib.nixosSystem
        {
          inherit system;
          modules = [
            ({...}: {
              # Overlays-module makes "pkgs.unstable" available in configuration.nix
              nixpkgs.overlays = [overlay-unstable];
            })
            ./configuration.nix
            # make home-manager as a module of nixos
            # so that home-manager configuration will be deployed automatically when executing `nixos-rebuild switch`
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.stalker = import ./stalker.nix;
            }
            agenix.nixosModules.default
            {
              # The agenix CLI (`agenix -e`, `--rekey`) comes from the flake
              # input: nixpkgs packages ragenix, not agenix.
              environment.systemPackages = [agenix.packages.${system}.default];
            }
          ];
        };
    };
  };
}
