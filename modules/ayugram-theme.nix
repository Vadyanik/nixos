{ pkgs, ... }:
let
  theme = import ../packages/ayugram-theme/package.nix { inherit pkgs; };
in {
  # Translucent chat background: Telegram paints solid wallpapers opaque, the patch applies windowBg alpha.
  nixpkgs.overlays = [
    (final: prev: {
      ayugram-desktop = prev.ayugram-desktop.override {
        telegram-desktop = prev.telegram-desktop.override {
          unwrapped = prev.telegram-desktop.unwrapped.overrideAttrs (attrs: {
            patches = (attrs.patches or [ ]) ++ [ ../packages/ayugram-theme/translucent-chat-background.patch ];
          });
        };
      };
    })
  ];
  environment.systemPackages = [ theme ];
  systemd.user.services.ayugram-quickshell-theme = {
    description = "Sync AyuGram theme file with the shared Quickshell palette";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionPathExists = "%h/.config/quickshell/bar/colors.css";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${theme}/bin/ayugram-quickshell-theme";
      UMask = "0077";
    };
  };
  systemd.user.paths.ayugram-quickshell-theme = {
    description = "Watch the shared wallpaper palette for AyuGram";
    wantedBy = [ "default.target" ];
    pathConfig.PathChanged = [ "%h/.config/quickshell/bar/colors.css" ];
  };
}
