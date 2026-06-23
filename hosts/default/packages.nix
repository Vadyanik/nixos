{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    neovim
    ghostty
    zellij
    tig
    tmux
    toilet
    git
    kitty
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

    bat # Syntax-highlighted cat replacement used in previews.
    eza # ls replacement with icons and tree support.

    bottom # System monitor.

    gradia
    fuse3
  ];
}
