{ pkgs }:
pkgs.runCommand "ayugram-quickshell-theme" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
  mkdir -p $out/bin $out/share/ayugram-quickshell
  cp ${./sync.py} $out/share/ayugram-quickshell/sync.py
  cp ${./night-base.palette} $out/share/ayugram-quickshell/night-base.palette
  makeWrapper ${pkgs.python3}/bin/python3 $out/bin/ayugram-quickshell-theme \
    --add-flags "$out/share/ayugram-quickshell/sync.py" \
    --set AYUGRAM_THEME_BASE "$out/share/ayugram-quickshell/night-base.palette"
''
