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
    EDITOR = "nvim";
    VISUAL = "nvim";
    GIT_EDITOR = "nvim";
    SUDO_EDITOR = "nvim";
  };

  environment.sessionVariables = {
    BROWSER = "librewolf";
    NIXOS_OZONE_WL = "1";
    VISUAL = "nvim";
    GIT_EDITOR = "nvim";
    SUDO_EDITOR = "nvim";
    PATH = [
      "$HOME/.local/bin"
    ];
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
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
      sh = "niri-session";
    };

    interactiveShellInit = ''
            export PATH="$HOME/.local/bin:$PATH"
            export PATH="$HOME/.npm-global/bin:$PATH"
            export PATH="$HOME/go/bin:$PATH"
            export EDITOR=nvim VISUAL=nvim GIT_EDITOR=nvim SUDO_EDITOR=nvim

            colors=(31 35 34 36 34 35 31 95 94 96 94 95 36 36)
            fastfetch_art=$(cat <<'FASTFETCH_ART'
                            ;                                                         
                            ED.                                                       
                            E#Wi                           L.                 G:      
                            E###G.                         EW:        ,ft t   E#,    :
                         .. E#fD#W;     f.     ;WE.     .. E##;       t#E Ej  E#t  .GE
        t      .DD.     ;W, E#t t##L    E#,   i#G      ;W, E###t      t#E E#, E#t j#K;
        EK:   ,WK.     j##, E#t  .E#K,  E#t  f#f      j##, E#fE#f     t#E E#t E#GK#f  
        E#t  i#D      G###, E#t    j##f E#t G#i      G###, E#t D#G    t#E E#t E##D.   
        E#t j#f     :E####, E#t    :E#K:E#jEW,     :E####, E#t  f#E.  t#E E#t E##Wi   
        E#tL#i     ;W#DG##, E#t   t##L  E##E.     ;W#DG##, E#t   t#K: t#E E#t E#jL#D: 
        E#WW,     j###DW##, E#t .D#W;   E#G      j###DW##, E#t    ;#W,t#E E#t E#t ,K#j
        E#K:     G##i,,G##, E#tiW#G.    E#t     G##i,,G##, E#t     :K#D#E E#t E#t   jD
        ED.    :K#K:   L##, E#K##i      E#t   :K#K:   L##, E#t      .E##E E#t j#t     
        t     ;##D.    L##, E##D.       EE.  ;##D.    L##, ..         G#E E#t  ,;     
              ,,,      .,,  E#t         t    ,,,      .,,              fE ,;.         
                            L:                                          ,             
      FASTFETCH_ART
            )

            # Draw the banner only when the terminal is wide enough to fit it.
            art_width=0
            while IFS= read -r line; do
              (( ''${#line} > art_width )) && art_width=''${#line}
            done <<< "$fastfetch_art"
            if (( ''${COLUMNS:-$(tput cols 2>/dev/null || echo 0)} >= art_width )); then
              color_index=0
              while IFS= read -r line; do
                printf '\033[%sm%s\033[0m\n' "''${colors[$((color_index % ''${#colors[@]} + 1))]}" "$line"
                ((color_index++))
              done <<< "$fastfetch_art"
            fi

            mkcd() {
              mkdir -p -- "$1" && cd -- "$1"
            }

            # Vim-style command-line navigation (Esc enters normal mode; i/a return to insert).
            bindkey -v
            KEYTIMEOUT=10
            bindkey -M viins '^A' beginning-of-line
            bindkey -M viins '^E' end-of-line
            bindkey -M viins '^[[1;5D' backward-word
            bindkey -M viins '^[[1;5C' forward-word
            bindkey -M viins '^[[5D' backward-word
            bindkey -M viins '^[[5C' forward-word
            bindkey -M viins '^[b' backward-word
            bindkey -M viins '^[f' forward-word
            bindkey -M viins '^[[H' beginning-of-line
            bindkey -M viins '^[[F' end-of-line
            bindkey -M viins '^[[3~' delete-char
            bindkey -M viins '^H' backward-kill-word
            bindkey -M viins '^[[A' up-line-or-search
            bindkey -M viins '^[[B' down-line-or-search

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
    "x-scheme-handler/mailto" = "librewolf.desktop";
    "x-scheme-handler/chrome" = "librewolf.desktop";
    "application/x-extension-xhtml" = "librewolf.desktop";
    "application/x-extension-xht" = "librewolf.desktop";
    "application/x-extension-shtml" = "librewolf.desktop";
    "application/x-extension-html" = "librewolf.desktop";
    "application/x-extension-htm" = "librewolf.desktop";
    "application/xhtml+xml" = "librewolf.desktop";
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

    "text/plain" = "nvim.desktop";
    "text/markdown" = "nvim.desktop";
    "application/json" = "nvim.desktop";
    "application/xml" = "nvim.desktop";
    "text/x-go" = "nvim.desktop";
    "text/x-python" = "nvim.desktop";
    "text/x-csharp" = "nvim.desktop";
    "application/x-shellscript" = "nvim.desktop";

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
