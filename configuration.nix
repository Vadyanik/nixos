{
  config,
  pkgs,
  inputs,
  ...
}:

let
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.system};
in
{
  imports = [
    ./hardware-configuration.nix
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  environment.variables = {
    XCURSOR_THEME = "macOS"; # или название конкретной темы из пакета
    XCURSOR_SIZE = "24";
  };

  networking.hostName = "nixos";

  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Kyiv";

  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "uk_UA.UTF-8";
    LC_IDENTIFICATION = "uk_UA.UTF-8";
    LC_MEASUREMENT = "uk_UA.UTF-8";
    LC_MONETARY = "uk_UA.UTF-8";
    LC_NAME = "uk_UA.UTF-8";
    LC_NUMERIC = "uk_UA.UTF-8";
    LC_PAPER = "uk_UA.UTF-8";
    LC_TELEPHONE = "uk_UA.UTF-8";
    LC_TIME = "uk_UA.UTF-8";
  };

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  users.users.vadyanik = {
    isNormalUser = true;
    shell = pkgs.zsh;
    description = "vadyanik";
    extraGroups = [
      "networkmanager"
      "wheel"
      "libvirtd"
      "kvm"
    ];
    packages = with pkgs; [ ];
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    histSize = 50000;
    histFile = "$HOME/.zsh_history";

    shellAliases = {
      claudedsp = "claude --dangerously-skip-permissions";
      cat = "bat";
      cd = "z";
      c = "clear";
      grep = "rg";
      la = "eza -la --icons --git";
      ll = "eza -l --icons --git";
      ls = "eza --icons --group-directories-first";
      lt = "eza --tree --icons --level=2";
      mkdir = "mkdir -p";
    };

    interactiveShellInit = ''
      # Paths migrated from /home/vadyanik/.zshrc and extended for local tools.
      export PATH="$HOME/.local/bin:$PATH"
      export PATH="$HOME/.npm-global/bin:$PATH"
      export PATH="$HOME/go/bin:$PATH"

      # Comfortable editing.
      bindkey -e
      bindkey '^[[1;5D' backward-word
      bindkey '^[[1;5C' forward-word
      bindkey '^[[5D' backward-word
      bindkey '^[[5C' forward-word
      bindkey '^[b' backward-word
      bindkey '^[f' forward-word
      bindkey '^[[H' beginning-of-line
      bindkey '^[[F' end-of-line
      bindkey '^[[3~' delete-char
      bindkey '^H' backward-kill-word
      bindkey '^[[A' up-line-or-search
      bindkey '^[[B' down-line-or-search

      # History that behaves well across multiple terminals.
      setopt APPEND_HISTORY
      setopt EXTENDED_HISTORY
      setopt HIST_EXPIRE_DUPS_FIRST
      setopt HIST_FIND_NO_DUPS
      setopt HIST_IGNORE_ALL_DUPS
      setopt HIST_IGNORE_SPACE
      setopt HIST_REDUCE_BLANKS
      setopt INC_APPEND_HISTORY
      setopt SHARE_HISTORY

      # Better completion UX.
      zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
      zstyle ':completion:*' menu select
      zstyle ':completion:*' group-name ""
      zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
      zstyle ':completion:*:warnings' format '%F{red}No matches for: %d%f'
      zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}

      # fzf restores a read-only zle option on zsh 5.9, so silence that harmless warning.
      if [[ -r ${pkgs.fzf}/share/fzf/completion.zsh ]]; then
        source ${pkgs.fzf}/share/fzf/completion.zsh 2>/dev/null
      fi
      if [[ -r ${pkgs.fzf}/share/fzf/key-bindings.zsh ]]; then
        source ${pkgs.fzf}/share/fzf/key-bindings.zsh 2>/dev/null
      fi

      # Quick fuzzy package runner migrated from /home/vadyanik/.zshrc.
      unalias nspf 2>/dev/null
      nspf() {
        local query="''${1:-.}"
        local selection
        selection=$(
          nix search nixpkgs "$query" --json 2>/dev/null \
            | jq -r 'to_entries[] | "\(.key | split(".") | last) \t \(.value.description)"' \
            | fzf --delimiter '\t' --with-nth 1 --preview 'echo {2}' --preview-window up:3:wrap \
            | awk '{print $1}'
        )

        if [[ -n "$selection" ]]; then
          nix run "nixpkgs#$selection"
        fi
      }
    '';
  };

  programs.fzf = {
    keybindings = false;
    fuzzyCompletion = false;
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.starship = {
    enable = true;
  };

  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  services.ollama = {
    enable = true;
    # Это автоматически добавит поддержку CUDA для NVIDIA
    package = pkgs.ollama-cuda;
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  programs.spicetify = {
    enable = true;
    theme = spicePkgs.themes.catppuccin;
    colorScheme = "mocha";

    enabledExtensions = with spicePkgs.extensions; [
      adblockify
      hidePodcasts
      shuffle
      beautifulLyrics
    ];
    enabledCustomApps = with spicePkgs.apps; [
      lyricsPlus
      ncsVisualizer
    ];
  };
  environment.sessionVariables = {
    BROWSER = "librewolf";
    PATH = [
      "$HOME/.local/bin"
    ];
  };

  # В NixOS эта опция называется xdg.mime, а не xdg.mimeApps
  xdg.mime.defaultApplications = {
    "text/html" = "librewolf.desktop";
    "x-scheme-handler/http" = "librewolf.desktop";
    "x-scheme-handler/https" = "librewolf.desktop";
    "x-scheme-handler/about" = "librewolf.desktop";
    "x-scheme-handler/unknown" = "librewolf.desktop";
    "inode/directory" = "org.kde.dolphin.desktop";
  };

  programs.steam.enable = true;
  environment.systemPackages = with pkgs; [
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
    inputs.zen-browser.packages.${stdenv.hostPlatform.system}.default
    jq
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

    imagemagick # для картинок
    shfmt # для форматирования bash
    tree-sitter
    nodejs_22

    sqlite # Критично для Snacks.picker (хранение истории и частоты файлов)
    lua51Packages.luarocks
    lua5_1
    trash-cli # Чтобы Snacks.explorer мог удалять файлы в корзину, а не навсегда
    ghostscript # Для отображения PDF в Neovim через Snacks.image
    ast-grep # Для умного структурного поиска в grug-far

    python311Packages.python-lsp-server # Базовый LSP для питона
    python311Packages.pip # Чтобы Mason мог доставлять пакеты сам
    pipx
    nodePackages.npm # Важно для большинства LSP (JS, TS, CSS, Tailwind)
    cargo # Для Rust-инструментов (стилизаторы, линтеры)

    stylua # Форматирование Lua-кода (критично для Neovim конфига)
    nodePackages.prettier # Универсальный форматировщик (HTML, JSON, MD, JS)
    checkstyle # Если работаешь с Java

    tectonic # Или pdflatex — для рендеринга формул LaTeX
    nodePackages.mermaid-cli # Чтобы прямо в Neovim видеть диаграммы Mermaid

    bat # Продвинутый cat с подсветкой синтаксиса (часто используется в превью)
    eza # Замена ls с иконками и деревом (Snacks его любит)

    bottom # Крутой системный монитор (btm)
  ];

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true; # Это упростит доступ к файлам в ~/
      swtpm.enable = true;
    };
  };
  programs.virt-manager.enable = true;

  services.mullvad-vpn.enable = true;
  services.logmein-hamachi.enable = true;
  networking.firewall.trustedInterfaces = [
    "ham0"
    "virbr0"
  ];

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
  };

  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      nspr
      nss
      mesa
      libdrm
      libgbm
      expat
      swtpm
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
      bibata-cursors

      sqlite # Gives Neovim access to libsqlite3.so
      stdenv.cc.cc.lib # Fixes 99% of "missing libstdc++.so.6" errors in Mason!
    ];

  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];

  programs.hyprland.enable = true;
  programs.waybar.enable = true;
  services.pulseaudio.enable = false;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
    config.common.default = "*";
  };

  programs.obs-studio = {
    enable = true;

    package = (
      pkgs.obs-studio.override {
        cudaSupport = true;
      }
    );

    plugins = with pkgs.obs-studio-plugins; [
      wlrobs
      obs-backgroundremoval
      obs-pipewire-audio-capture
      obs-gstreamer
      obs-vkcapture
    ];
  };

  programs.obs-studio.enableVirtualCamera = true;

  boot.extraModulePackages = with config.boot.kernelPackages; [
    v4l2loopback
  ];

  boot.kernelModules = [ "v4l2loopback" ];

  boot.extraModprobeConfig = ''
    # Твоя камера для OBS
    options v4l2loopback devices=1 video_nr=1 card_label="OBS Virtual Camera" exclusive_caps=1

    # Исправление для запуска Windows в Quickemu
    options kvm ignore_msrs=1
    options kvm report_ignored_msrs=0
  '';
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  services.blueman.enable = true;

  services.flatpak.enable = true;

  services.input-remapper.enable = true;

  # Включаем сам Polkit (на всякий случай, обычно включен по умолчанию)
  security.polkit.enable = true;

  # Создаем пользовательский сервис, который сам найдет нужный путь к пакету
  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "polkit-gnome-authentication-agent-1";
    wantedBy = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };
  };

  system.stateVersion = "25.11";
}
