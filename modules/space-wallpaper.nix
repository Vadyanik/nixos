{ pkgs, ... }:
let
  wallpaper = import ../packages/space-wallpaper/package.nix { inherit pkgs; };
  settings = builtins.fromJSON (builtins.readFile ../packages/space-wallpaper/settings.json);
in
{
  environment.etc."space-wallpaper/settings.json".source = ../packages/space-wallpaper/settings.json;

  systemd.user.services.space-wallpaper-daemon = {
    description = "Space wallpaper Wayland background";
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.awww}/bin/awww-daemon --no-cache";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  systemd.user.services.space-wallpaper-update = {
    description = "Refresh the offline NASA space wallpaper library";
    unitConfig.ConditionUser = "vadyanik";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${wallpaper}/bin/wallpaper-update";
      Nice = 15;
      IOSchedulingClass = "idle";
      TimeoutStartSec = "2h";
      MemoryMax = "2G";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      CacheDirectory = "space-wallpaper";
      StateDirectory = "space-wallpaper";
      UMask = "0077";
    };
  };

  systemd.user.timers.space-wallpaper-update = {
    description = "Daily space wallpaper cache refresh";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = settings.update_calendar;
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };
}
