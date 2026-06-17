# Copilot Instructions

## Build, test, and lint

- Evaluate the NixOS system without switching:
  ```bash
  nix eval path:/etc/nixos#nixosConfigurations.nixos.config.system.build.toplevel.drvPath
  ```
- Build the system closure without activating it:
  ```bash
  nix build path:/etc/nixos#nixosConfigurations.nixos.config.system.build.toplevel
  ```
- Activate the host configuration:
  ```bash
  sudo nixos-rebuild switch --flake /etc/nixos#nixos
  ```
- Prefer a one-shot test activation for system changes when appropriate:
  ```bash
  sudo nixos-rebuild test --flake /etc/nixos#nixos
  ```
- Check the rebuild helper script:
  ```bash
  bash -n /etc/nixos/rebuild.sh
  ```

There is no application test suite in this repository. For targeted validation, use the `path:/etc/nixos` flake form while new files are unstaged.

## High-level architecture

- This repo is a single-host NixOS flake for `nixos`.
- `flake.nix` is the entrypoint. It pins inputs and wires `nixosConfigurations.nixos` to `hosts/default/configuration.nix`.
- `hosts/default/configuration.nix` is the host layer: it sets the hostname, imports hardware, package, system, and user modules, and owns `system.stateVersion`.
- `modules/system.nix` contains machine-wide configuration: boot, networking, locale, NVIDIA, audio, virtualization, portals, Bluetooth, Flatpak, SSH, garbage collection, and related services.
- `modules/user.nix` contains user/session configuration: the `vadyanik` account, zsh, shell aliases, PATH/session variables, Spicetify, MIME defaults, and user services.
- `hosts/default/packages.nix` is the system package list for `environment.systemPackages`.
- `packages/` holds custom package definitions, such as wrapped AppImage packages.

## Key conventions

- Keep Nix files declarative, grouped by concern, and two-space indented.
- Put packages in `hosts/default/packages.nix`; keep service and system settings in `modules/system.nix` or `modules/user.nix`.
- Treat `hosts/default/hardware-configuration.nix` as generated; do not edit or regenerate it unless hardware layout changes and the user asks for it.
- Do not add `modules/vnix.nix`.
- Use the `path:/etc/nixos` flake form for local validation when new files are not yet staged, because normal flake evaluation only sees Git-tracked files.
- Keep comments and documentation in English.
- Recent commit prefixes in this repo are concise and conventional: `feat:`, `fix:`, `chore:`, and `rebuild:`.
