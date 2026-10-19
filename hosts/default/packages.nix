{ pkgs, ... }:

let
  xmcl-app = pkgs.appimageTools.wrapType2 {
    pname = "xmcl";
    version = "0.62.0";
    src = pkgs.fetchurl {
      url = "https://github.com/Voxelum/x-minecraft-launcher/releases/download/v0.62.0/xmcl-0.62.0-x86_64.AppImage";
      sha256 = "sha256-u3HZLTqeDia1gblEn02Xtk3bOwbFanWh2RAJhc4el1U=";
    };
    extraPkgs =
      pkgs: with pkgs; [
        libGL
        libGLU
        glib
        nss
        nspr
        atk
        cups
        libdrm
        mesa
        libxkbcommon
        pango
        (lib.getLib stdenv.cc.cc)
        alsa-lib
        dbus
        gtk3
        expat
        udev
        vulkan-loader
      ];
  };
  xmcl = pkgs.writeShellScriptBin "xmcl" ''
    exec ${xmcl-app}/bin/xmcl --no-sandbox "$@"
  '';
  xmcl-desktop = pkgs.makeDesktopItem {
    name = "xmcl";
    desktopName = "X Minecraft Launcher";
    exec = "xmcl %U";
    terminal = false;
    categories = [ "Game" ];
    startupWMClass = "XMCL";
  };
in
{
  environment.systemPackages = with pkgs; [
    # vnix:start
    ghostty
    fastfetch
    zellij
    tig
    tmux
    toilet
    git
    hyprlock
    rofi
    github-cli
    librewolf
    pavucontrol
    opencode
    chromium
    apple-cursor
    gcc
    polkit_gnome
    tor-browser
    ulauncher
    blockbench
    xmcl-app
    xmcl
    xmcl-desktop
    quickemu
    dotnet-sdk_8
    jdk21_headless
    fzf
    cava
    quickshell
    lavat
    cbonsai
    pipes
    aalib # Includes aafire.
    genact
    unimatrix
    globe-cli # Executable: globe.
    (import ../../packages/desktop-widgets/programs.nix { inherit pkgs; }).sortty
    (import ../../packages/desktop-widgets/programs.nix { inherit pkgs; }).ascii-rain
    (import ../../packages/desktop-widgets/package.nix { inherit pkgs; })
    grim
    slurp
    wl-clipboard
    unzip
    ayugram-desktop
    zoom-us
    qview
    glib
    dconf
    at-spi2-core
    gsettings-desktop-schemas
    kdePackages.dolphin
    kdePackages.kservice
    kdePackages.dolphin-plugins
    kdePackages.kio-extras
    kdePackages.kio-admin
    kdePackages.kio-fuse
    kdePackages.ark
    kdePackages.konsole
    kdePackages.kate
    kdePackages.ffmpegthumbs
    kdePackages.kdegraphics-thumbnailers
    kdePackages.kimageformats
    kdePackages.qtimageformats
    kdePackages.baloo-widgets
    p7zip
    mpv
    easyeffects
    jq
    awww
    matugen
    (import ../../packages/space-wallpaper/package.nix { inherit pkgs; })
    go
    csharpier

    (prismlauncher.override {
      prismlauncher-unwrapped = pkgs.prismlauncher-unwrapped.overrideAttrs (old: {
        version = "11.1.1";
        src = pkgs.fetchFromGitHub {
          owner = "PrismLauncher";
          repo = "PrismLauncher";
          tag = "11.1.1";
          hash = "sha256-vSCiCDatoRnA1vpqLDuelC/2cBCKp+fXGT/O0DYjHuk=";
        };
      });
      additionalLibs = with pkgs; [
        nspr
        nss
        mesa
        libdrm
        libgbm
        expat
        alsa-lib
        cups
        dbus
        glib
        pango
        atk
        libx11
        libxcomposite
        libxdamage
        libxrandr
        libxcb
        libxext
        libxfixes
        libxkbcommon
        cairo
        gtk3
      ];
    })

    mullvad-vpn

    ripgrep
    fd
    lazygit

    python3
    wget
    unzip

    imagemagick # Image tooling.
    shfmt # Bash formatter.
    tree-sitter
    nodejs_22 # Node.js and npm for JS, TS, CSS, and Tailwind LSPs.

    sqlite # Gives Snacks.picker sqlite history and frequency storage.
    trash-cli # Lets Snacks.explorer move files to trash instead of deleting permanently.
    ghostscript # Enables PDF previews in Neovim through Snacks.image.
    ast-grep # Structural search for grug-far.

    python3Packages.python-lsp-server # Base Python LSP.
    python3Packages.pip # Lets Mason install Python packages when needed.
    cargo # Rust tooling for formatters and linters.

     # Lua formatter for the Neovim config.
    prettier # Formatter for HTML, JSON, Markdown, JS, and more.
     # Java checks.

     # LaTeX engine for formula rendering.
     # Mermaid diagram rendering.

    anki
    bat # Syntax-highlighted cat replacement used in previews.
    eza # ls replacement with icons and tree support.

    bottom # System monitor.

    fuse3
    icu
    ngrok
    localsend
    rclone
    ffmpeg
    imagemagick
    libreoffice
    cliphist
    wl-clipboard
    uv
    ncspot
    playerctl
    psst
    zip
    claude-desktop
    claude-code
    qbittorrent
    nvd
    # vnix:end
  ];
}
