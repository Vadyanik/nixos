{ config, pkgs, inputs, ... }:

let
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.system};
in
{
  imports =
    [
      ./hardware-configuration.nix
    ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Kyiv";

  # Select internationalisation properties.
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
    extraGroups = [ "networkmanager" "wheel" "libvirtd" "kvm" ];
    packages = with pkgs; [];
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
     easyeffects
     grim 
     slurp 
     wl-clipboard
     blockbench
     unzip
     ayugram-desktop
     zoom-us
     qview
     mpv
     zed-editor
     inputs.zen-browser.packages.${stdenv.hostPlatform.system}.default
     jq
     kdePackages.kate
     kdePackages.dolphin
     hyprpaper
     zenity
     (prismlauncher.override {
    additionalLibs = with pkgs; [
      nspr nss mesa libdrm libgbm
      expat alsa-lib cups dbus glib pango atk
      libx11 libxcomposite libxdamage 
      libxrandr libxcb libxext libxfixes
      libxkbcommon cairo gtk3
    ];
  })
     mullvad-vpn
     logmein-hamachi
     haguichi
  ];

virtualisation.libvirtd.enable = true;
programs.virt-manager.enable = true;

services.mullvad-vpn.enable = true;
services.logmein-hamachi.enable = true;
networking.firewall.trustedInterfaces = [ "ham0" ];

  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      nspr nss mesa libdrm libgbm
      expat alsa-lib cups dbus glib pango atk
      libx11 libxcomposite libxdamage 
      libxrandr libxcb libxext libxfixes
      libxkbcommon cairo gtk3
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

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  services.blueman.enable = true;

  services.flatpak.enable = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?

}
