{ pkgs, ... }:
let
  widgets = import ../packages/desktop-widgets/package.nix { inherit pkgs; };
in {
  systemd.user.services.quickshell-widgets = {
    description = "Quickshell audio visualizer and terminal animations";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${widgets}/bin/desktop-widgets";
      Restart = "on-failure";
      RestartSec = 3;
      Environment = "QT_QPA_PLATFORM=wayland";
    };
  };
}
