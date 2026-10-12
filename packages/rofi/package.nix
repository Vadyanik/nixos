{ pkgs }:
pkgs.runCommand "desktop-rofi" { nativeBuildInputs = [ pkgs.makeWrapper pkgs.python3 pkgs.bash ]; } ''
  mkdir -p $out/share/rofi $out/bin
  cp -r ${./.}/* $out/share/rofi/
  rm $out/share/rofi/package.nix
  chmod -R u+w $out/share/rofi
  patchShebangs $out/share/rofi/scripts
  for entry in launcher themed-rofi; do
    if [ "$entry" = launcher ]; then name=rofi-launcher; else name=themed-rofi; fi
    makeWrapper ${pkgs.python3}/bin/python3 $out/bin/$name \
      --add-flags "$out/share/rofi/scripts/$entry.py" \
      --set ROFI_CONFIG_DIR "$out/share/rofi" \
      --prefix PATH : '${pkgs.lib.makeBinPath [ pkgs.rofi pkgs.niri pkgs.hyprland pkgs.chromium pkgs.glib ]}'
  done
''
