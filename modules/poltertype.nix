{ lib, pkgs, ... }:
let
  desktopTools = import ../packages/desktop-session/package.nix { inherit pkgs; };
  poltertype = import ../packages/poltertype/package.nix { inherit pkgs; };
in {
  environment.systemPackages = [ poltertype ];
  systemd.user.services."dev.opensource.poltertype" = {
    description = "PolterType with native GTK and compositor IPC";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
    serviceConfig = {
      ExecStart = "${desktopTools}/bin/desktop-session-env ${poltertype}/bin/poltertype-daemon";
      Restart = "on-failure";
      RestartSec = 5;
      Environment = [ "PATH=/run/current-system/sw/bin" ];
    };
  };
  # Adopt the existing launcher/unit, leaving config.toml and wordlists mutable.
  system.activationScripts.poltertypeConfiguration = lib.stringAfter [ "users" ] ''
    polterHome=/home/vadyanik
    polterArchive="$polterHome/.local/state/desktop-nix-migration/$(date +%Y%m%d-%H%M%S)-poltertype"
    adopt_polter_link() {
      source="$1"
      target="$2"
      if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then return; fi
      if [ -e "$target" ] || [ -L "$target" ]; then
        saved="$polterArchive/''${target#"$polterHome/"}"
        mkdir -p "$(dirname "$saved")"
        mv "$target" "$saved"
      fi
      mkdir -p "$(dirname "$target")"
      ln -sfn "$source" "$target"
      chown -h vadyanik:users "$target"
    }
    adopt_polter_link /etc/systemd/user/dev.opensource.poltertype.service "$polterHome/.config/systemd/user/dev.opensource.poltertype.service"
    adopt_polter_link ${poltertype}/share/applications/poltertype.desktop "$polterHome/.local/share/applications/poltertype.desktop"
    target="$polterHome/.config/systemd/user/dev.opensource.poltertype.service.d"
    if [ -e "$target" ]; then
      mkdir -p "$polterArchive/.config/systemd/user"
      mv "$target" "$polterArchive/.config/systemd/user/"
    fi
    if [ -d "$polterArchive" ]; then chown -R vadyanik:users "$polterArchive"; fi
  '';
}
