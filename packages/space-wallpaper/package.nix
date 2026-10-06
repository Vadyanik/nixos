{ pkgs }:
let
  python = pkgs.python3.withPackages (ps: [ ps.pillow ]);
  oxanium = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/sevmeyer/oxanium/a8f39e0c71186190027a093e9001459410192d1e/fonts/ttf/Oxanium-SemiBold.ttf";
    hash = "sha256-4td+xO5nsBUhZq311jkzYFUKASwgZuDUWJBT4UpzPNw=";
  };
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "space-wallpaper";
  version = "1.0";
  src = ./.;
  nativeBuildInputs = [ pkgs.makeWrapper ];
  dontBuild = true;
  installPhase = ''
    mkdir -p $out/lib/space-wallpaper $out/bin
    cp wallpaper.py settings.json $out/lib/space-wallpaper/
    for action in next update notify workspace; do
      makeWrapper ${python}/bin/python3 $out/bin/wallpaper-$action \
        --add-flags "$out/lib/space-wallpaper/wallpaper.py $action" \
        --set SPACE_WALLPAPER_FONT ${oxanium} \
        --prefix PATH : ${
          pkgs.lib.makeBinPath [
            pkgs.hyprland
            pkgs.awww
            pkgs.matugen
            pkgs.systemd
          ]
        }
    done
  '';
}
