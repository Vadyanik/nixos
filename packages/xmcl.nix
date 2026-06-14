{
  lib,
  appimageTools,
  fetchurl,
}:

let
  pname = "xmcl";
  version = "0.56.7";

  src = fetchurl {
    url = "https://github.com/Voxelum/x-minecraft-launcher/releases/download/v${version}/xmcl-${version}-x86_64.AppImage";
    hash = "sha256-AhwE1n+w+1h7waY+SZDeN5b/1j4Es3+/oso+fraHax0=";
  };

  appimageContents = appimageTools.extractType2 {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -m 444 -D ${appimageContents}/xmcl.desktop \
      $out/share/applications/xmcl.desktop
    install -m 444 -D ${appimageContents}/xmcl.png \
      $out/share/icons/hicolor/512x512/apps/xmcl.png
    substituteInPlace $out/share/applications/xmcl.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=xmcl'
  '';

  meta = {
    description = "X Minecraft Launcher";
    homepage = "https://www.xmcl.app/";
    license = lib.licenses.mit;
    mainProgram = "xmcl";
    platforms = [ "x86_64-linux" ];
  };
}
