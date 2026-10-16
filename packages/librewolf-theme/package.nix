{ pkgs }:
pkgs.runCommand "librewolf-quickshell-theme" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
  mkdir -p $out/bin $out/share/librewolf-quickshell
  cp ${./sync.py} $out/share/librewolf-quickshell/sync.py
  cp ${./userChrome.css} $out/share/librewolf-quickshell/userChrome.css
  cp ${./userContent.css} $out/share/librewolf-quickshell/userContent.css
  makeWrapper ${pkgs.python3}/bin/python3 $out/bin/librewolf-quickshell-theme \
    --add-flags "$out/share/librewolf-quickshell/sync.py" \
    --set LIBREWOLF_THEME_ASSETS "$out/share/librewolf-quickshell"
''
