{ pkgs }:
pkgs.runCommand "vesktop-quickshell-theme" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
  mkdir -p $out/bin $out/share/vesktop-quickshell
  cp ${./sync.py} $out/share/vesktop-quickshell/sync.py
  cp ${./theme.css} $out/share/vesktop-quickshell/theme.css
  makeWrapper ${pkgs.python3}/bin/python3 $out/bin/vesktop-quickshell-theme \
    --add-flags "$out/share/vesktop-quickshell/sync.py" \
    --set VESKTOP_THEME_CSS "$out/share/vesktop-quickshell/theme.css"
''
