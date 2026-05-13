# Repository Guidelines

## Project Structure & Module Organization

This repository is a NixOS flake for the `nixos` host. The flake entrypoint is `flake.nix`; pinned input revisions live in `flake.lock`.

- `hosts/default/configuration.nix`: host entrypoint, imports, hostname, and `system.stateVersion`.
- `hosts/default/hardware-configuration.nix`: generated hardware config; avoid manual edits unless hardware layout changes.
- `hosts/default/packages.nix`: packages installed through `environment.systemPackages`.
- `modules/system.nix`: system-wide boot, networking, locale, GPU, audio, virtualization, services, fonts, and security options.
- `modules/user.nix`: user account, zsh, shell tools, Spicetify, MIME defaults, cursor/session variables, and user services.
- `rebuild.sh`: helper script for staging, rebuilding, committing, and pushing changes.

There are no application sources, test suites, or asset pipelines in this repo.

## Build, Test, and Development Commands

Use these commands from `/etc/nixos`:

```bash
nix eval path:/etc/nixos#nixosConfigurations.nixos.config.system.build.toplevel.drvPath
```

Evaluates the NixOS system without switching.

```bash
nix build path:/etc/nixos#nixosConfigurations.nixos.config.system.build.toplevel
```

Builds the system closure without activating it.

```bash
sudo nixos-rebuild switch --flake /etc/nixos#nixos
```

Builds and activates the host configuration.

```bash
bash -n /etc/nixos/rebuild.sh
```

Checks the rebuild script syntax.

## Coding Style & Naming Conventions

Keep Nix files two-space indented, declarative, and grouped by concern. Prefer descriptive module names such as `system.nix`, `user.nix`, or `desktop.nix`. Keep all comments and documentation in English. Avoid mixing package lists with service configuration; put packages in `hosts/default/packages.nix`.

## Testing Guidelines

Before switching, run `nix eval` or `nix build` with the `path:` flake form so newly created files are included before they are staged. Run `bash -n rebuild.sh` after editing shell code. For hardware or boot changes, prefer `nixos-rebuild test` before `switch` when possible.

## Commit & Pull Request Guidelines

Recent commits use concise conventional-style prefixes: `feat:`, `fix:`, `chore:`, and `rebuild:`. Keep messages imperative and specific, for example `feat: Add Bluetooth tooling`.

For pull requests, include a short summary, list touched modules, and mention validation commands run. Link related issues when available. Screenshots are usually unnecessary unless the change affects desktop UI behavior.

## Agent-Specific Instructions

Do not create `modules/vnix.nix`. Do not delete or regenerate `hardware-configuration.nix` without explicit user approval. If adding new files, remember flakes evaluate Git-tracked sources by default; stage new files before testing with a normal `--flake` path, or use `path:/etc/nixos` for local validation.
