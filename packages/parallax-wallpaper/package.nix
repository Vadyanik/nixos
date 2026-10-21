{ pkgs }:
let
  python = pkgs.python3.withPackages (ps: [ ps.evdev ]);
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "parallax-wallpaper";
  version = "1.0";
  src = ./.;
  nativeBuildInputs = [ pkgs.makeWrapper ];
  dontBuild = true;
  installPhase = ''
    share=$out/share/parallax-wallpaper
    mkdir -p $share $out/bin
    cp -r assets wallpapers.json parallax-pointer.py parallax-wallpaper.py shell.qml Neko.qml $share/
    substituteInPlace $share/shell.qml \
      --replace-fail '@python@' '${python}/bin/python3' \
      --replace-fail '@share@' "$share/"
    makeWrapper ${pkgs.python3}/bin/python3 $out/bin/parallax-wallpaper \
      --add-flags "$share/parallax-wallpaper.py" \
      --set PARALLAX_WALLPAPER_SHARE "$share"
    makeWrapper ${pkgs.quickshell}/bin/quickshell $out/bin/parallax-wallpaper-shell \
      --add-flags "--no-duplicate --config $share"
  '';
}
