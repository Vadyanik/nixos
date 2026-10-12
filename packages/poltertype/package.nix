{ pkgs }:
let
  version = "0.36.4";
  desktopTools = import ../desktop-session/package.nix { inherit pkgs; };
  # Preserve the locally installed artifact (including prior fixes), store its
  # content in Nix, and run against native GTK instead of an AppImage FHS bubble.
  src = pkgs.fetchurl {
    url = "https://github.com/Just-Code-NET/PolterType/releases/download/v${version}/poltertype-${version}-x86_64.AppImage";
    hash = "sha256-pV4TJX4AVK74Ld5dbQiKUmuWuzeCqeOoAfN+ZRXj95Y=";
  };
  contents = pkgs.appimageTools.extractType2 {
    pname = "poltertype";
    inherit src version;
  };
  native = pkgs.stdenv.mkDerivation {
    pname = "poltertype-native";
    inherit version;
    src = contents;
    nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.makeWrapper pkgs.patchelf ];
    buildInputs = [ pkgs.gtk3 pkgs.xdotool pkgs.alsa-lib pkgs.stdenv.cc.cc.lib ];
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin $out/share
      install -m755 usr/bin/poltertype $out/bin/poltertype-native
      # This release imports only xdo_new, xdo_free and
      # xdo_send_keysequence_window. Recent nixpkgs xdotool releases renamed
      # libxdo's SONAME from .3 to .4 without removing these symbols.
      if [ -e ${pkgs.xdotool}/lib/libxdo.so.4 ]; then
        patchelf --replace-needed libxdo.so.3 libxdo.so.4 $out/bin/poltertype-native
      fi
      cp -r usr/share/poltertype $out/share/
      mkdir -p $out/share/icons/hicolor/256x256/apps
      cp poltertype.png $out/share/icons/hicolor/256x256/apps/poltertype.png
      wrapProgram $out/bin/poltertype-native \
        --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath [ pkgs.libayatana-appindicator ]} \
        --prefix XDG_DATA_DIRS : ${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}:$out/share
      runHook postInstall
    '';
  };
in pkgs.runCommand "poltertype-${version}" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
  mkdir -p $out/bin $out/share/poltertype $out/share/applications
  cp ${./niri-adapter.py} $out/share/poltertype/niri-adapter.py
  makeWrapper ${pkgs.python3}/bin/python3 $out/bin/poltertype-daemon \
    --add-flags "$out/share/poltertype/niri-adapter.py ${native}/bin/poltertype-native"
  makeWrapper ${native}/bin/poltertype-native $out/bin/poltertype \
    --run 'if [ -n "''${NIRI_SOCKET:-}" ]; then export HYPRLAND_INSTANCE_SIGNATURE=poltertype-niri; export POLTERTYPE_LAYOUT_BACKEND=hyprland; fi'
  cat > $out/bin/poltertype-launch <<LAUNCH
  #!${pkgs.bash}/bin/bash
  set -e
  ${desktopTools}/bin/desktop-session-env --import
  ${pkgs.systemd}/bin/systemctl --user start dev.opensource.poltertype.service
  if [[ -n "\''${NIRI_SOCKET:-}" ]]; then
    for ((attempt = 0; attempt < 30; attempt++)); do
      [[ -S "\$XDG_RUNTIME_DIR/hypr/poltertype-niri/.socket.sock" ]] && break
      ${pkgs.coreutils}/bin/sleep 0.1
    done
  fi
  exec ${desktopTools}/bin/desktop-session-env $out/bin/poltertype --settings
  LAUNCH
  chmod +x $out/bin/poltertype-launch
  ln -s ${native}/share/icons $out/share/icons
  cat > $out/share/applications/poltertype.desktop <<DESKTOP
  [Desktop Entry]
  Type=Application
  Name=PolterType
  GenericName=Keyboard Layout Switcher
  Comment=Auto-detect and fix wrong-keyboard-layout typing
  Exec=$out/bin/poltertype-launch
  Icon=poltertype
  Terminal=false
  Categories=Utility;System;
  Keywords=keyboard;layout;language;input;
  StartupNotify=false
  StartupWMClass=poltertype
  DESKTOP
''
