{ pkgs }:
let
  runtime = pkgs.lib.makeBinPath (with pkgs; [
    niri hyprland hyprlock python3 procps libnotify wl-clipboard grim slurp flameshot
    swappy systemd dbus coreutils cliphist rofi chromium glib
  ]);
in pkgs.runCommand "desktop-session-tools" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
  mkdir -p $out/bin $out/share/desktop-session
  cp ${./hyprlock.conf} $out/share/desktop-session/hyprlock.conf
  cp ${./session-env.py} $out/share/desktop-session/session-env.py
  makeWrapper ${pkgs.python3}/bin/python3 $out/bin/desktop-session-env \
    --add-flags "$out/share/desktop-session/session-env.py" --prefix PATH : '${runtime}'
  cp ${./desktop.py} $out/share/desktop-session/desktop.py
  cp ${./ghostty-wallpaper-theme.py} $out/share/desktop-session/ghostty-wallpaper-theme.py
  for action in focus mru lock scratchpad force-close poltertype screenshot; do
    makeWrapper ${pkgs.python3}/bin/python3 $out/bin/desktop-$action \
      --add-flags "$out/share/desktop-session/desktop.py $action" \
      --set DESKTOP_LOCK_CONFIG "$out/share/desktop-session/hyprlock.conf" \
      --prefix PATH : '${runtime}'
  done
  makeWrapper ${pkgs.python3}/bin/python3 $out/bin/ghostty-wallpaper-theme \
    --add-flags "$out/share/desktop-session/ghostty-wallpaper-theme.py" --prefix PATH : '${runtime}'
''
