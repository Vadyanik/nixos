{
  description = "NixOS unstable flake for nixos";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    awww.url = "git+https://codeberg.org/LGFae/awww";

    codex-desktop-linux.url = "github:ilysenko/codex-desktop-linux";

    claude-desktop = {
      url = "github:aaddrick/claude-desktop-debian";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      spicetify-nix,
      codex-desktop-linux,
      claude-desktop,
      ...
    }@inputs:
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/default/configuration.nix
          spicetify-nix.nixosModules.default
          codex-desktop-linux.nixosModules.default
          {
            nixpkgs.overlays = [ claude-desktop.overlays.default ];
            programs.codexDesktopLinux = {
              enable = true;
              computerUseUi.enable = true;
            };
            programs.ydotool.enable = true;
            users.users.vadyanik.extraGroups = [ "ydotool" ];
          }
        ];
      };
    };
}
