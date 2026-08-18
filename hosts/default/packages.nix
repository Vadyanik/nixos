{ pkgs, ... }:

let
  xmcl-app = pkgs.appimageTools.wrapType2 {
    pname = "xmcl";
    version = "0.62.0";
    src = pkgs.fetchurl {
      url = "https://github.com/Voxelum/x-minecraft-launcher/releases/download/v0.62.0/xmcl-0.62.0-x86_64.AppImage";
      sha256 = "sha256-u3HZLTqeDia1gblEn02Xtk3bOwbFanWh2RAJhc4el1U=";
    };
    extraPkgs = pkgs: with pkgs; [
      libGL libGLU glib nss nspr atk cups libdrm mesa libxkbcommon pango
      (lib.getLib stdenv.cc.cc) alsa-lib dbus gtk3 expat udev vulkan-loader
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
    neovim
    ghostty
    fastfetch
    zellij
    tig
    hypridle
    tmux
    toilet
    git
    kitty
    hyprlock
    appimage-run
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
    fzf
    bubblewrap
    cava
    bc
    grim
    slurp
    wl-clipboard
    unzip
    ayugram-desktop
    obsidian
    zoom-us
    ollama
    qview
    kdePackages.dolphin
    mpv
    vlc
    easyeffects
    jq
    wineWow64Packages.stagingFull
    winetricks
    hyprpaper
    zenity
    go

    (prismlauncher.override {
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
    lua51Packages.luarocks
    lua5_1
    trash-cli # Lets Snacks.explorer move files to trash instead of deleting permanently.
    ghostscript # Enables PDF previews in Neovim through Snacks.image.
    ast-grep # Structural search for grug-far.

    python3Packages.python-lsp-server # Base Python LSP.
    python3Packages.pip # Lets Mason install Python packages when needed.
    pipx
    cargo # Rust tooling for formatters and linters.

    stylua # Lua formatter for the Neovim config.
    prettier # Formatter for HTML, JSON, Markdown, JS, and more.
    checkstyle # Java checks.

    tectonic # LaTeX engine for formula rendering.
    mermaid-cli # Mermaid diagram rendering.

    anki
    bat # Syntax-highlighted cat replacement used in previews.
    eza # ls replacement with icons and tree support.

    bottom # System monitor.

    gradia
    fuse3
    icu
    ngrok
  ];
}
