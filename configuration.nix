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
    description = "vadyanik";
    extraGroups = [
      "networkmanager"
      "wheel"
      "libvirtd"
      "kvm"
    ];
    packages = with pkgs; [ ];
  };

  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
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

  programs.steam.enable = true;
  environment.systemPackages = with pkgs; [
    neovim
    ghostty
    git
    kitty
    rofi
    librewolf
    pavucontrol
    discord
    opencode
    starship
    wtype
    claude-code
    gcc
    dotnet-sdk_8
    fzf
    cava
    bc
    easyeffects
    grim
    slurp
    wl-clipboard
    blockbench
    unzip
    ayugram-desktop
    obsidian
    zoom-us
    qview
    mpv
    zed-editor
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
    logmein-hamachi
    haguichi
    # Core
    ripgrep
    fd
    lazygit

    # Mason / LSP requirements
    python3
    wget
    unzip

    # Optional
    imagemagick # для картинок
    shfmt # для форматирования bash
    tree-sitter
    nodejs_22

    # 1. Системные зависимости для плагинов Neovim
    sqlite # Критично для Snacks.picker (хранение истории и частоты файлов)
    lua51Packages.luarocks
    lua5_1
    trash-cli # Чтобы Snacks.explorer мог удалять файлы в корзину, а не навсегда
    ghostscript # Для отображения PDF в Neovim через Snacks.image
    ast-grep # Для умного структурного поиска в grug-far

    # 2. Окружение для Mason (чтобы ставилось вообще всё)
    python311Packages.python-lsp-server # Базовый LSP для питона
    python311Packages.pip # Чтобы Mason мог доставлять пакеты сам
    pipx
    nodePackages.npm # Важно для большинства LSP (JS, TS, CSS, Tailwind)
    cargo # Для Rust-инструментов (стилизаторы, линтеры)

    # 3. Дополнительные форматировщики и инструменты
    stylua # Форматирование Lua-кода (критично для Neovim конфига)
    nodePackages.prettier # Универсальный форматировщик (HTML, JSON, MD, JS)
    checkstyle # Если работаешь с Java

    # 4. Рендеринг (для Snacks и работы с Markdown)
    tectonic # Или pdflatex — для рендеринга формул LaTeX
    nodePackages.mermaid-cli # Чтобы прямо в Neovim видеть диаграммы Mermaid

    # 5. Утилиты для терминала (улучшают опыт)
    bat # Продвинутый cat с подсветкой синтаксиса (часто используется в превью)
    eza # Замена ls с иконками и деревом (Snacks его любит)

    bottom # Крутой системный монитор (btm)
  ];

  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;

  services.mullvad-vpn.enable = true;
  services.logmein-hamachi.enable = true;
  networking.firewall.trustedInterfaces = [ "ham0" ];

  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
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

      sqlite # Gives Neovim access to libsqlite3.so
      stdenv.cc.cc.lib # Fixes 99% of "missing libstdc++.so.6" errors in Mason!
    ];

  };

  services.keyd = {
    enable = true;
    keyboards = {
      default = {
        ids = [ "*" ];
        extraConfig = builtins.readFile ./configs/keyd/default.conf;
      };
    };
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
    options v4l2loopback devices=1 video_nr=1 card_label="OBS Virtual Camera" exclusive_caps=1
  '';

  security.polkit.enable = true;

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  services.blueman.enable = true;

  services.flatpak.enable = true;

  system.stateVersion = "25.11";
}
