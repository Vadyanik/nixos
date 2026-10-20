# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Single-host NixOS flake (`nixosConfigurations.nixos`, user `vadyanik`) plus the sources of a custom Niri + Quickshell desktop. See `AGENTS.md` for the full guidelines; the essentials are below.

## Rebuilding and managing the config: use VNix

Use `vnix` (`~/.local/bin/vnix`, source https://git.vadyanik.me/vadyanik/VNix, `vnix help` for the manual) for rebuilds and package management instead of calling `nixos-rebuild` or `rebuild.sh` directly. It is already initialised here (`.vnix/config.json`, managed block in `hosts/default/packages.nix` between `# vnix:start` / `# vnix:end`). This is unrelated to the forbidden `modules/vnix.nix`.

```bash
vnix install PKG...      # add attributes to the managed block (plain attributes only)
vnix remove PKG...
vnix packages list
vnix update              # nix flake update only; review `git diff flake.lock`
vnix plan                # flake check + dry-build + dry-activate; optional, usually skip it and go straight to rebuild (user's preference)
vnix rebuild             # sudo nixos-rebuild switch --flake /etc/nixos#nixos, then hooks
vnix drift | stats | generations list
```

Anything beyond plain package attributes (modules, services, overrides) is edited by hand in the Nix files, then `vnix rebuild` (`vnix plan` is optional and mostly unnecessary). Caution: `vnix rebuild` is configured to `git add .`, commit (via `aic -p`), and **force-push the current branch** to `origin` (`git_push_branch` is empty, so it follows whatever branch is checked out), and runs a profile-stats hook. The user has given standing permission: Claude may run `vnix rebuild` at any time without asking first (including its commit and force-push of the current branch). Never force-push `main` by hand; merge into it normally.

## Manual validation

Use the `path:` flake form so unstaged new files are evaluated (plain `.#` only sees Git-tracked files).

```bash
nix eval path:/etc/nixos#nixosConfigurations.nixos.config.system.build.toplevel.drvPath   # fast eval check
nix build path:/etc/nixos#nixosConfigurations.nixos.config.system.build.toplevel          # build, no activation
bash -n rebuild.sh                                                                         # legacy helper syntax check
```

There is no CI or lint step. The only tests are the legacy `legacy/space-wallpaper/test_wallpaper.py` (unittest, needs Pillow) and `packages/desktop-widgets/check.py <built-package-path>` (animation smoke test).

`rebuild.sh` is the older hand-written equivalent of `vnix rebuild`; prefer VNix.

## Architecture

- `hosts/default/configuration.nix` imports hardware, `packages.nix` (all `environment.systemPackages`), and the modules. `modules/system.nix` = machine-wide; `modules/user.nix` = account/zsh/Spicetify/MIME/user services. Never create `modules/vnix.nix`; never edit/regenerate `hardware-configuration.nix` without approval.
- Feature modules (`niri-desktop.nix`, `parallax-wallpaper.nix`, `desktop-widgets.nix`, `librewolf-theme.nix`, `poltertype.nix`) each pair with a source directory under `packages/<name>/` that holds the actual QML/Python/KDL/shell. The module builds the package (`import ../packages/<name>/package.nix { inherit pkgs; }`), wires systemd user services, and installs config via `environment.etc`.
- Desktop layering: `niri-desktop.nix` builds a **patched Niri** (`packages/niri/workspace-zoom.patch`, asserts Niri version `26.04` — rebase the patch before bumping nixpkgs' Niri), `desktop-session` (shared Python tooling, `desktop-session-env` imports the session environment for services), the Quickshell bar (`packages/quickshell-bar`, scripts in `scripts/`, built with `qsb` shaders and `hotkeys.json` generated from `packages/niri/hotkeys.kdl`), and Rofi. `desktop-session-start` starts the user services.
- Config files are shipped to `/etc/xdg/...` and **adopted** into `~/.config/...` as symlinks by an activation script in `niri-desktop.nix` (replaced local files are archived under `~/.local/state/desktop-nix-migration/`). Edit the repo sources, not the `~/.config` links.
- Hyprland stays installed alongside Niri; don't launch a second compositor to validate config while one is running on the seat.
- Wallpapers: `parallax-wallpaper` draws two-layer parallax art (Quickshell, mouse-driven) from `packages/parallax-wallpaper/assets/<id>/`; switch with `parallax-wallpaper set <id>` (also installs that wallpaper's palette into `colors.css`). The old NASA rotation lives in `legacy/` and is not imported.
- Flake inputs of note: `claude-desktop` (overlay), `codex-desktop-linux` (NixOS module), `spicetify-nix`, `awww` (wallpaper daemon).

## Branch workflow

- Anything bigger than installing a single package (a new feature, module, theme, or multi-file change) is developed on its own branch `feat/<name>` (or `fix/<name>`), created from `main` before the first edit. Small changes stay on `main`.
- `vnix rebuild` on the branch builds and pushes that branch; `main` is untouched until the merge.
- When the user is happy, merge with `git merge --no-ff feat/<name>` into `main` (plain push, no force), then delete the branch. Ask before merging unless told to.
- To undo, use `git reset` to the wanted commit (or drop the unmerged branch), never a new "revert" commit, unless the user asks for one.

## Conventions

- Two-space Nix, grouped by concern; packages only in `hosts/default/packages.nix`; comments/docs in English.
- Commit prefixes: `feat:`, `fix:`, `chore:`, `rebuild:`; imperative messages.
- Quickshell bar and Control Center stay terminal-like and text-led: no pills, cards, decorative blocks or image icons, and no overview indicators in the bar (use a compositor-level cue such as a wallpaper-palette vignette).
