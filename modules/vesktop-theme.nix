{ pkgs, ... }:
let
  theme = import ../packages/vesktop-theme/package.nix { inherit pkgs; };
in {
  environment.systemPackages = [ theme ];
  systemd.user.services.vesktop-quickshell-theme = {
    description = "Sync Vesktop quickCss with the shared Quickshell palette";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionPathExists = "%h/.config/quickshell/bar/colors.css";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${theme}/bin/vesktop-quickshell-theme";
      UMask = "0077";
    };
  };
  systemd.user.paths.vesktop-quickshell-theme = {
    description = "Watch the shared wallpaper palette for Vesktop";
    wantedBy = [ "default.target" ];
    pathConfig.PathChanged = [ "%h/.config/quickshell/bar/colors.css" ];
  };
}
