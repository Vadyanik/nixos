{ config, lib, pkgs, ... }:
let
  niriZoom = pkgs.niri.overrideAttrs (old: assert lib.assertMsg (old.version == "26.04")
    "workspace-zoom.patch targets Niri 26.04; rebase it before upgrading Niri"; {
  patches = (old.patches or []) ++ [ ../packages/niri/workspace-zoom.patch ../packages/niri/pointer-position.patch ];
  # Skip the package's separate cargo test build; the user wants to validate desktop behavior directly.
  doCheck = false;
  env = (old.env or {}) // { NIRI_BUILD_COMMIT = "Nixpkgs-workspace-zoom"; };
});
  workspaceZoom = pkgs.writeScriptBin "desktop-workspace-zoom" (
    "#!${pkgs.python3}/bin/python3\n" + builtins.readFile ../packages/niri/workspace-zoom.py
  );
  desktopTools = import ../packages/desktop-session/package.nix { inherit pkgs; };
  bar = import ../packages/quickshell-bar/package.nix { inherit pkgs desktopTools; };
  rofi = import ../packages/rofi/package.nix { inherit pkgs; };
  sessionStart = pkgs.writeShellApplication {
    name = "desktop-session-start";
    runtimeInputs = [ pkgs.systemd pkgs.dbus ];
    text = ''
      ${desktopTools}/bin/desktop-session-env --import
      systemctl --user start parallax-wallpaper.service quickshell-bar.service quickshell-widgets.service
      systemctl --user start polkit-gnome-authentication-agent-1.service desktop-clipboard-text.service desktop-clipboard-image.service
      systemctl --user start dev.opensource.poltertype.service
    '';
  };
  clipboardService = type: {
    description = "Record ${type} clipboard history";
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type ${type} --watch ${pkgs.cliphist}/bin/cliphist store";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
in {
  programs.niri = {
    enable = true;
    package = niriZoom;
    useNautilus = false;
  };
  environment.systemPackages = [
    desktopTools bar rofi sessionStart workspaceZoom pkgs.xwayland-satellite pkgs.swappy
  ];
  environment.etc."xdg/niri/config.kdl".source = ../packages/niri/config.kdl;
  environment.etc."xdg/niri/hotkeys.kdl".source = ../packages/niri/hotkeys.kdl;
  environment.etc."xdg/ghostty/config".source = ../packages/ghostty/config;
  environment.etc."xdg/ghostty/cursor-warp.glsl".source = ../packages/ghostty/cursor-warp.glsl;
  programs.zsh.shellAliases.sn = "niri-session";

  systemd.user.services.quickshell-bar = {
    description = "Shared Quickshell bar, control and notification centers";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${desktopTools}/bin/desktop-session-env ${bar}/bin/desktop-bar";
      Environment = [
        "QT_QPA_PLATFORM=wayland"
        "PATH=%h/.npm-global/bin:%h/.local/bin:%h/.nix-profile/bin:/run/current-system/sw/bin"
      ];
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
  systemd.user.services.quickshell-claude-usage = {
    description = "Refresh Claude subscription limits and preserve usage history";
    path = with pkgs; [ bash coreutils curl jq python3 util-linux systemd quickshell ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${bar}/share/quickshell/bar/scripts/claude_usage.sh fetch";
      TimeoutStartSec = 20;
    };
  };
  systemd.user.timers.quickshell-claude-usage = {
    description = "Refresh Claude limits every two minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnActiveSec = 1;
      OnUnitActiveSec = 120;
      AccuracySec = 1;
    };
  };
  systemd.user.services.desktop-clipboard-text = clipboardService "text";
  systemd.user.services.desktop-clipboard-image = clipboardService "image";
  systemd.user.services.ghostty-wallpaper-theme = {
    description = "Sync Ghostty with the active wallpaper palette";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${desktopTools}/bin/ghostty-wallpaper-theme";
    };
  };
  systemd.user.paths.ghostty-wallpaper-theme = {
    description = "Watch the shared wallpaper palette for Ghostty";
    wantedBy = [ "default.target" ];
    pathConfig.PathChanged = "%h/.config/quickshell/bar/colors.css";
  };

  # Adopt the existing non-Home-Manager desktop without discarding mutable data.
  # Subsequent switches update only the Nix-owned symlinks.
  system.activationScripts.desktopConfiguration = lib.stringAfter [ "users" ] ''
    desktopHome=/home/vadyanik
    desktopArchive="$desktopHome/.local/state/desktop-nix-migration/$(date +%Y%m%d-%H%M%S)"
    adopt_desktop_link() {
      source="$1"
      target="$2"
      if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then return; fi
      if [ -e "$target" ] || [ -L "$target" ]; then
        saved="$desktopArchive/''${target#"$desktopHome/"}"
        mkdir -p "$(dirname "$saved")"
        mv "$target" "$saved"
      fi
      mkdir -p "$(dirname "$target")"
      ln -sfn "$source" "$target"
      chown -h vadyanik:users "$target"
    }
    for source in ${bar}/share/quickshell/bar/*; do
      adopt_desktop_link "$source" "$desktopHome/.config/quickshell/bar/$(basename "$source")"
    done
    adopt_desktop_link ${desktopTools}/share/desktop-session/hyprlock.conf "$desktopHome/.config/hypr/hyprlock.conf"
    adopt_desktop_link /etc/xdg/ghostty/config "$desktopHome/.config/ghostty/config"
    adopt_desktop_link /etc/xdg/niri/config.kdl "$desktopHome/.config/niri/config.kdl"
    adopt_desktop_link ${rofi}/bin/rofi-launcher "$desktopHome/.config/rofi/scripts/launcher.py"
    adopt_desktop_link ${rofi}/bin/themed-rofi "$desktopHome/.config/rofi/scripts/themed-rofi.py"
    adopt_desktop_link ${desktopTools}/bin/ghostty-wallpaper-theme "$desktopHome/.local/bin/ghostty-wallpaper-theme"
    for unit in quickshell-bar.service ghostty-wallpaper-theme.service ghostty-wallpaper-theme.path quickshell-claude-usage.service quickshell-claude-usage.timer; do
      adopt_desktop_link "/etc/systemd/user/$unit" "$desktopHome/.config/systemd/user/$unit"
    done
    target="$desktopHome/.config/systemd/user/space-wallpaper-daemon.service.d"
    if [ -e "$target" ]; then
      saved="$desktopArchive/.config/systemd/user/space-wallpaper-daemon.service.d"
      mkdir -p "$(dirname "$saved")"
      mv "$target" "$saved"
    fi
    chown -R vadyanik:users "$desktopHome/.config/niri"
    if [ -d "$desktopHome/.local/state/desktop-nix-migration" ]; then
      chown -R vadyanik:users "$desktopHome/.local/state/desktop-nix-migration"
    fi
  '';
}
