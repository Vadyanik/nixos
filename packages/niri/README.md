# Niri desktop alongside Hyprland

`modules/niri-desktop.nix` enables Niri using the flake's pinned Nixpkgs package
(currently Niri 26.04). It installs this KDL config through
`environment.etc."xdg/niri/config.kdl"` and adopts
`~/.config/niri/config.kdl` as a link to that file. Desktop commands, Rofi, the
shared Quickshell shell, wallpaper integration, and user services are built from
the NixOS source tree. Existing local files replaced by adoption are archived in
`~/.local/state/desktop-nix-migration/<timestamp>/`.

Hyprland remains installed and available. Start Niri with `niri-session` (the `sn`
zsh alias) from a TTY, or select its session in a display manager. End the active
compositor session before starting another on the same seat. Do not launch a
second compositor using the session startup commands just to validate its config.

## Appearance and integrations

The configuration preserves the current HDMI-A-1 resolution and scale
(3840×2160, 60 Hz, 1.5), macOS cursor at size 24, zero gaps, square corners, the
2-pixel cyan/green active-border gradient, gray inactive border, full window
opacity, and small dark shadows. Other displays use Niri's automatic defaults.
Niri 26.04 provides native background blur, enabled for windows and the existing
Quickshell/Rofi layer surfaces. Its Kawase offset and saturation approximate the
Hyprland blur settings; identical pixels are not expected across compositors.
The same cubic Bezier curves are used for workspace and window animations.
Application windows slide upward from one window height below their final
position in 480 ms, and slide downward on closing in 400 ms. Neither transition
fades or scales the window.

Quickshell's bar, Control Center, Notification Center, notification popups, media
popup, desktop widgets, and wallpaper palette share one source and service setup
across sessions. Session startup imports the current compositor's environment
before starting the services; Chromium and Steam are not launched automatically.
Clipboard history uses session-scoped `wl-paste` user services.

Niri always provides an unnamed empty workspace below the named workspaces.
With ten numbered workspaces and `magic`, the native overview therefore has
twelve entries; the user chose to retain this stock Niri behavior.

Named workspaces `1` through `10` retain the original number keys even when empty
or reordered. The bar shows active or occupied workspaces, hiding the empty
reserve and the inactive magic workspace. The `magic` workspace supports the scratchpad helper. No application
is forced onto a particular workspace.

## Existing shortcuts

`Super` is the main modifier in a normal Niri session. A nested Niri test window
uses `Alt` for bindings written with `Mod` to reduce host shortcut collisions.

| Shortcut | Action |
| --- | --- |
| Super+Q / T / E | Ghostty / Chromium / Dolphin |
| Super+R | The existing themed Rofi application/search/calculator launcher |
| Super+Tab / Super+Shift+Tab | Control Center / Notification Center |
| Super+C / Super+Shift+C | Close window / force-close its process |
| Super+V | Toggle floating |
| Super+F | Maximize column |
| Super+Shift+F | Toggle fullscreen |
| Super+H / Super+L | Focus column left/right |
| Super+J / Super+K | Next/previous workspace (down/up) |
| Super+Shift+H / Super+Shift+L | Move column left/right |
| Super+Shift+J / Super+Shift+K | Move window to workspace below/above and follow |
| Super+arrows | Focus adjacent column or window |
| Super+1…9,0 | Workspaces 1…10 |
| Super+Shift+1…9,0 | Move focused window to workspaces 1…10 and follow it |
| Super+O / Super+Shift+O | Visit/return from magic / move window to magic |
| Super+Space | Previous keyboard language; quick second press reaches the third |
| Ctrl+Alt+Shift+L | English keyboard layout |
| Ctrl+Alt+Shift+Super+L | Russian keyboard layout |
| Super+F1 | Start voice recording |
| Super+Shift+F1 | Finish recording and transcribe |
| Super+Ctrl+F1 | Cancel recording or transcription |
| Super+Z | Focus Codex, or launch it if absent |
| Super+B | Themed clipboard history |
| Super+P / Shift+Print | Select screenshot region and copy it |
| Print | Select screenshot region and open annotation editor |
| Super+Alt+P | Toggle the Poltertype exception for the active application |
| Super+wheel down/up | Quickshell volume up/down |
| Super+left/right mouse drag | Niri native window move/resize |
| Audio/media/brightness keys | Existing volume, mute, playback, and brightness commands |

Niri uses its native screenshot selection and Swappy for annotation, copying the
result to the clipboard. Hyprland retains Grim/Slurp and Flameshot.

The original three keyboard layouts (`us,ua,ru`) and `caps:swapescape` are retained.
There is no additional XKB group toggle that would double-trigger Super+Space.

## Additional Niri shortcuts

| Shortcut | Action |
| --- | --- |
| Super+S | Workspace overview |
| Super+W | Toggle tabbed column |
| Super+Shift+V | Focus floating/tiling layout |
| Super+Ctrl+F | Expand column to remaining available width |
| Super+Ctrl+C | Center current column |
| Super+Shift+R | Cycle column widths: one-third, half, two-thirds, full |
| Super+Ctrl+R | Cycle window heights |
| Super+- / Super+= | Adjust column width by 10% |
| Super+Shift+- / Super+Shift+= | Adjust window height by 10% |
| Super+[ / Super+] | Consume or expel window into adjacent column |
| Super+, / Super+. | Consume next window / expel bottom window |
| Super+Ctrl+arrows | Move column horizontally or window vertically |
| Super+Home / Super+End | Focus first/last column |
| Super+Ctrl+PageUp / PageDown | Move window to previous/next workspace |
| Super+Shift+PageUp / PageDown | Reorder workspace |
| Super+Shift+arrows | Focus monitor in that direction |
| Super+Ctrl+Shift+arrows | Move window to monitor in that direction |
| Alt+Tab / Alt+Shift+Tab | Native recent-window switcher forward/backward |
| Alt+grave / Alt+Shift+grave | Recent windows from the same application |
| Ctrl+Print / Alt+Print | Copy screen/window screenshot |
| Super+/ (no Shift) | Full searchable shortcut list |
| Super+Escape | Escape application shortcut inhibition |

Niri's native gestures scroll columns horizontally with three fingers and switch
workspaces vertically. Four-finger vertical swipes open/close the overview. Its
top-left hot corner also opens the overview. The top-right hot corner toggles
the Quickshell Control Center. Dictation uses Super+F1 to start,
Super+Shift+F1 to transcribe, and Super+Ctrl+F1 to cancel.

## Compositor differences

- Niri's layout is a scrolling strip of columns. Hyprland's dwindle/pseudotiling
  split tree has no exact equivalent; stacking, tabs, column widths, and
  consume/expel shortcuts supply its layout controls.
- `magic` is an ordinary named workspace. The helper remembers the source
  workspace and returns there on the second press. It cannot overlay a special
  workspace on top of the current workspace as Hyprland does.
- Picture-in-Picture windows float with a starting size of 640×360. Niri has no
  equivalent of Hyprland's sticky/pinned window above every workspace and
  fullscreen window, or its `keep_aspect_ratio` rule. These windows remain on
  their workspace and can be moved manually.
- Glava is configured as an unfocused floating window on its current workspace
  with no shadow. Its Hyprland pin and permanent no-focus rules are unavailable;
  the shared Quickshell desktop widgets are the portable desktop layer.
- The individual `epic-mouse-v1` sensitivity override cannot be expressed in
  Niri 26.04's per-device-type input configuration. The global mouse speed is
  retained.
- Hyprland's suppress-maximize request and empty-XWayland-window dragging rules
  have no direct KDL equivalents. Niri uses its native window management and
  Xwayland Satellite integration.
- Animation directions follow Niri's vertical workspaces and horizontal columns.
  Timings and curves are close approximations, rather than identical Hyprland
  rendering.

## Validation

Validate without activating a compositor session:

```sh
niri validate -c /etc/xdg/niri/config.kdl
nix eval path:/etc/nixos#nixosConfigurations.nixos.config.system.build.toplevel.drvPath
nix build path:/etc/nixos#nixosConfigurations.nixos.config.system.build.toplevel
```

The KDL was validated with the exact Niri 26.04 binary from the pinned Nixpkgs.
The NixOS system was built and activated with nixos-rebuild switch. Both session
packages are registered. The shared bar, widgets, wallpaper daemon, and Ghostty
palette path remained active in Hyprland without automatic failure restarts.

Two isolated nested Niri sessions verified actual rendering of the bar, Control
Center, notification center and popups, wallpaper captions, and desktop widgets.
Workspace switches changed the displayed image and shared palette through the
real Niri socket and a separate awww daemon. Keyboard layout events and the
language-history helper were verified through real IPC (0 to 1 to 2). Test state,
cache, and notification bus were isolated from the live desktop.

Physical shortcuts, DRM/NVIDIA monitor startup, screencasting, annotation-editor
interaction, and locking still require checking after logging into Niri on the
real seat. Nested rendering does not verify those interactions.

Official references: [configuration](https://niri-wm.github.io/niri/Configuration:-Introduction.html),
[keybindings](https://niri-wm.github.io/niri/Configuration:-Key-Bindings.html),
[window rules](https://niri-wm.github.io/niri/Configuration:-Window-Rules.html),
[background blur](https://niri-wm.github.io/niri/Configuration:-Miscellaneous.html#blur),
[named workspaces](https://niri-wm.github.io/niri/Configuration:-Named-Workspaces.html),
[animations](https://niri-wm.github.io/niri/Configuration:-Animations.html).
