{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./packages.nix
    ../../modules/system.nix
    ../../modules/space-wallpaper.nix
    ../../modules/desktop-widgets.nix
    ../../modules/niri-desktop.nix
    ../../modules/librewolf-theme.nix
    ../../modules/poltertype.nix
    ../../modules/user.nix
  ];

  networking.hostName = "nixos";

  system.stateVersion = "25.11";
}
