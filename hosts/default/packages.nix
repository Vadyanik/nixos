{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    stockfish
    pychess
    neovim
    ghostty
    git
    kitty
    rofi
    librewolf
    pavucontrol
    opencode
    chromium
    apple-cursor
    wtype
    claude-code
    gcc
    vesktop
    polkit_gnome
    lunar-client
    tor-browser
    ulauncher
    blockbench
    whisper-cpp
    quickemu
    dotnet-sdk_8
    fzf
    bubblewrap
    cava
    bc
    qbittorrent
    easyeffects
    grim
    slurp
    wl-clipboard
    unzip
    ayugram-desktop
    obsidian
    zoom-us
    qview
    kdePackages.dolphin
    mpv
    vlc
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
    nodejs_22

    sqlite # Gives Snacks.picker sqlite history and frequency storage.
    lua51Packages.luarocks
    lua5_1
    trash-cli # Lets Snacks.explorer move files to trash instead of deleting permanently.
    ghostscript # Enables PDF previews in Neovim through Snacks.image.
    ast-grep # Structural search for grug-far.

    python311Packages.python-lsp-server # Base Python LSP.
    python311Packages.pip # Lets Mason install Python packages when needed.
    pipx
    nodePackages.npm # Required by many JS, TS, CSS, and Tailwind LSPs.
    cargo # Rust tooling for formatters and linters.

    stylua # Lua formatter for the Neovim config.
    nodePackages.prettier # Formatter for HTML, JSON, Markdown, JS, and more.
    checkstyle # Java checks.

    tectonic # LaTeX engine for formula rendering.
    nodePackages.mermaid-cli # Mermaid diagram rendering.

    bat # Syntax-highlighted cat replacement used in previews.
    eza # ls replacement with icons and tree support.

    bottom # System monitor.

    kdePackages.kdenlive # Video editor.
    firefox # Web browser.
  ];
}
