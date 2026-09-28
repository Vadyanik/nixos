{
  pkgs,
  inputs,
  ...
}:

let
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.system};
in
{
  environment.variables = {
    XCURSOR_THEME = "macOS";
    XCURSOR_SIZE = "24";
  };

  environment.sessionVariables = {
    BROWSER = "librewolf";
    NIXOS_OZONE_WL = "1";
    PATH = [
      "$HOME/.local/bin"
    ];
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
      "docker"
      "input"
      "uinput"
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
      cd = "z";
      c = "clear";
      cx = "codex";
      ff = "fastfetch";
      oc = "opencode";
      g = "git";
      ga = "git add .";
      gd = "git diff";
      gp = "git push";
      gs = "git status";
      grep = "rg";
      la = "eza -la --icons --git";
      ll = "eza -l --icons --git";
      ls = "eza --icons --group-directories-first";
      lt = "eza --tree --icons --level=3";
      gtree = "git log --graph --decorate --oneline --all";
      mkdir = "mkdir -p";
      v = "nvim";
      sh = "start-hyprland";
      unzip = "unzip -d";
    };

    interactiveShellInit = ''
      export PATH="$HOME/.local/bin:$PATH"
      export PATH="$HOME/.npm-global/bin:$PATH"
      export PATH="$HOME/go/bin:$PATH"

      fastfetch

      mkcd() {
        mkdir -p -- "$1" && cd -- "$1"
      }

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

  xdg.mime.defaultApplications = {
    "text/html" = "librewolf.desktop";
    "x-scheme-handler/http" = "librewolf.desktop";
    "x-scheme-handler/https" = "librewolf.desktop";
    "x-scheme-handler/about" = "librewolf.desktop";
    "x-scheme-handler/unknown" = "librewolf.desktop";
    "inode/directory" = "org.kde.dolphin.desktop";
    "image/avif" = "com.interversehq.qView.desktop";
    "image/bmp" = "com.interversehq.qView.desktop";
    "image/gif" = "com.interversehq.qView.desktop";
    "image/jpeg" = "com.interversehq.qView.desktop";
    "image/png" = "com.interversehq.qView.desktop";
    "image/svg+xml" = "com.interversehq.qView.desktop";
    "image/tiff" = "com.interversehq.qView.desktop";
    "image/webp" = "com.interversehq.qView.desktop";

    "application/pdf" = "okularApplication_pdf.desktop";
    "application/epub+zip" = "okularApplication_epub.desktop";
    "application/x-cbr" = "okularApplication_comicbook.desktop";
    "application/x-cbz" = "okularApplication_comicbook.desktop";

    "text/plain" = "org.kde.kate.desktop";
    "text/markdown" = "org.kde.kate.desktop";
    "application/json" = "org.kde.kate.desktop";
    "application/xml" = "org.kde.kate.desktop";

    "application/msword" = "writer.desktop";
    "application/rtf" = "writer.desktop";
    "application/vnd.oasis.opendocument.text" = "writer.desktop";
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = "writer.desktop";
    "application/vnd.ms-excel" = "calc.desktop";
    "application/vnd.oasis.opendocument.spreadsheet" = "calc.desktop";
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = "calc.desktop";
    "text/csv" = "calc.desktop";
    "application/vnd.ms-powerpoint" = "impress.desktop";
    "application/vnd.oasis.opendocument.presentation" = "impress.desktop";
    "application/vnd.openxmlformats-officedocument.presentationml.presentation" = "impress.desktop";

    "application/zip" = "org.kde.ark.desktop";
    "application/x-7z-compressed" = "org.kde.ark.desktop";
    "application/x-bzip2" = "org.kde.ark.desktop";
    "application/x-gzip" = "org.kde.ark.desktop";
    "application/x-rar" = "org.kde.ark.desktop";
    "application/x-tar" = "org.kde.ark.desktop";
    "application/x-xz" = "org.kde.ark.desktop";
    "application/zstd" = "org.kde.ark.desktop";

    "audio/aac" = "vlc.desktop";
    "audio/flac" = "vlc.desktop";
    "audio/mp4" = "vlc.desktop";
    "audio/mpeg" = "vlc.desktop";
    "audio/ogg" = "vlc.desktop";
    "audio/x-wav" = "vlc.desktop";
    "video/mp4" = "vlc.desktop";
    "video/mpeg" = "vlc.desktop";
    "video/quicktime" = "vlc.desktop";
    "video/webm" = "vlc.desktop";
    "video/x-flv" = "vlc.desktop";
    "video/x-matroska" = "vlc.desktop";
    "video/x-msvideo" = "vlc.desktop";
  };

  environment.etc."xdg/dolphinrc".text = ''
    [ContextMenu]
    ShowCopyMoveMenu=true

    [General]
    BrowseThroughArchives=true
    OpenExternallyCalledFolderInNewTab=true
    ShowFullPath=true
    ShowFullPathInTitlebar=true
    ShowToolTips=true
    ShowZoomSlider=true
    UseTabForSwitchingSplitView=true

    [VersionControl]
    enabledPlugins=Git
  '';

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

  programs.nix-ld = {
    enable = true;

    libraries = with pkgs; [
      xorg.libXtst
      xorg.libX11
      xorg.libXi
    ];
  };
}
