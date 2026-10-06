{ pkgs }:
let
  python = pkgs.python3.withPackages (p: [ p.pyte p.pillow ]);
  runtime = pkgs.lib.makeBinPath [
    pkgs.lavat pkgs.cbonsai pkgs.pipes pkgs.aalib pkgs.genact
    pkgs.unimatrix pkgs.bash pkgs.ncurses
  ];
in pkgs.runCommand "desktop-widgets" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
  mkdir -p $out/share/desktop-widgets $out/bin
  cp ${./.}/{shell.qml,cava.conf,caption-size.py,animation-bridge.py} $out/share/desktop-widgets/
  substituteInPlace $out/share/desktop-widgets/shell.qml \
    --replace-fail '@python@' '${python}/bin/python3' \
    --replace-fail '@configDir@' "$out/share/desktop-widgets/"
  makeWrapper ${pkgs.quickshell}/bin/quickshell $out/bin/desktop-widgets \
    --add-flags "--no-duplicate --config $out/share/desktop-widgets" \
    --prefix PATH : '${runtime}' \
    --set TERMINFO '${pkgs.ncurses}/share/terminfo'
''
