{
  config,
  pkgs,
  ...
}:

{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nixpkgs.config.allowUnfree = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.extraModulePackages = with config.boot.kernelPackages; [
    v4l2loopback
  ];

  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  boot.kernelModules = [ "v4l2loopback" ];

  boot.extraModprobeConfig = ''
    # OBS virtual camera.
    options v4l2loopback devices=1 video_nr=1 card_label="OBS Virtual Camera" exclusive_caps=1

    # Quickemu Windows guest compatibility.
    options kvm ignore_msrs=1
    options kvm report_ignored_msrs=0
  '';

  networking.networkmanager.enable = true;

  networking.firewall.trustedInterfaces = [
    "ham0"
    "virbr0"
  ];

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
    options = "caps:swapescape";
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  programs.steam.enable = true;

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
    };
  };

  programs.virt-manager.enable = true;
  virtualisation.docker.enable = true;
  services.mullvad-vpn.enable = true;
  services.logmein-hamachi.enable = true;
  services.ollama.enable = true;

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

      sqlite # Gives Neovim access to libsqlite3.so.
      stdenv.cc.cc.lib # Provides libstdc++.so.6 for Mason tools.
    ];
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    open-dyslexic
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

#programs.obs-studio = {
  #   enable = true;
  #
  # package = pkgs.obs-studio.override {
  #   cudaSupport = true;
  # };
  #
  # plugins = with pkgs.obs-studio-plugins; [
  #   wlrobs
  #   obs-backgroundremoval
  #   obs-pipewire-audio-capture
  #   obs-gstreamer
  #   obs-vkcapture
  # ];
  #};

  # programs.obs-studio.enableVirtualCamera = true;

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  services.blueman.enable = true;

  services.flatpak.enable = true;

  services.input-remapper.enable = true;

  security.polkit.enable = true;
  security.sudo.extraRules = [
    {
      users = [ "vadyanik" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/nixos-rebuild";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  nix.optimise.automatic = true;
}
