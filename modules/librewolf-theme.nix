{ lib, pkgs, ... }:
let
  theme = import ../packages/librewolf-theme/package.nix { inherit pkgs; };
in {
  environment.systemPackages = [ theme ];
  # Retire only the temporary user units installed before the first root switch.
  system.activationScripts.librewolfThemeBootstrap = lib.stringAfter [ "users" ] ''
    for unit in librewolf-quickshell-theme.service librewolf-quickshell-theme.path; do
      target="/home/vadyanik/.config/systemd/user/$unit"
      if [ -f "$target" ] && grep -q '^# Quickshell LibreWolf bootstrap$' "$target"; then
        archive="/home/vadyanik/.local/state/librewolf-quickshell/bootstrap-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$archive"
        mv "$target" "$archive/$unit"
        ln -s "/etc/systemd/user/$unit" "$target"
        chown -R vadyanik:users "$archive"
        chown -h vadyanik:users "$target"
      fi
    done
  '';
  systemd.user.services.librewolf-quickshell-theme = {
    description = "Sync LibreWolf CSS with the shared Quickshell palette";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionPathExists = "%h/.config/quickshell/bar/colors.css";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${theme}/bin/librewolf-quickshell-theme";
      UMask = "0077";
    };
  };
  systemd.user.paths.librewolf-quickshell-theme = {
    description = "Watch the shared wallpaper palette for LibreWolf";
    wantedBy = [ "default.target" ];
    pathConfig.PathChanged = [
      "%h/.config/quickshell/bar/colors.css"
      "%h/.config/librewolf/librewolf/profiles.ini"
    ];
  };
}
