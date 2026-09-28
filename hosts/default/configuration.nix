{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./packages.nix
    ../../modules/system.nix
    ../../modules/space-wallpaper.nix
    ../../modules/user.nix
  ];

  networking.hostName = "nixos";

  system.stateVersion = "25.11";
}
