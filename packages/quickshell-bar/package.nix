{ pkgs, desktopTools }:
let
  runtime = pkgs.lib.makeBinPath (with pkgs; [
    desktopTools niri hyprland bash python3 jq coreutils gnused gawk gnugrep curl
    playerctl bluez procps glib systemd util-linux iproute2 pipewire wireplumber
    networkmanager mullvad-vpn input-remapper brightnessctl libnotify rofi
  ]);
in pkgs.runCommand "quickshell-bar" { nativeBuildInputs = [ pkgs.makeWrapper pkgs.python3 pkgs.bash pkgs.qt6.qtshadertools ]; } ''
  mkdir -p $out/share/quickshell/bar $out/bin
  cp -r ${./.}/* $out/share/quickshell/bar/
  rm $out/share/quickshell/bar/package.nix
  chmod -R u+w $out/share/quickshell/bar
  python3 ${./scripts/niri_hotkeys.py} ${../niri/hotkeys.kdl} > $out/share/quickshell/bar/hotkeys.json
  qsb --glsl "100 es,120,150" -o $out/share/quickshell/bar/shaders/control-reveal.frag.qsb ${./shaders/control-reveal.frag}
  patchShebangs $out/share/quickshell/bar/scripts
  makeWrapper ${pkgs.quickshell}/bin/quickshell $out/bin/desktop-bar \
    --add-flags '--no-duplicate --config bar' \
    --prefix PATH : '${runtime}'
''
