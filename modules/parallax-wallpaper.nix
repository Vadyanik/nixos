{ pkgs, ... }:
let
  wallpaper = import ../packages/parallax-wallpaper/package.nix { inherit pkgs; };
in
{
  environment.systemPackages = [ wallpaper ];

  systemd.user.services.parallax-wallpaper = {
    description = "Layered parallax wallpaper driven by mouse motion";
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      # Apply the palette that matches the selected wallpaper before drawing it.
      ExecStartPre = "${wallpaper}/bin/parallax-wallpaper apply";
      ExecStart = "${wallpaper}/bin/parallax-wallpaper-shell";
      Environment = "QT_QPA_PLATFORM=wayland";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
}
