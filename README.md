# NixOS Configuration

Personal NixOS flake for the `nixos` host.

## Layout

```text
.
├── flake.nix
├── flake.lock
├── hosts/
│   └── default/
│       ├── configuration.nix
│       ├── hardware-configuration.nix
│       └── packages.nix
├── modules/
│   ├── system.nix
│   └── user.nix
└── rebuild.sh
```

## Files

- `flake.nix` is the flake entrypoint. It wires inputs and points the `nixos` configuration at `hosts/default/configuration.nix`.
- `flake.lock` pins exact input revisions.
- `hosts/default/configuration.nix` is the host entrypoint. Keep host-specific imports, hostname, and `system.stateVersion` here.
- `hosts/default/hardware-configuration.nix` is generated hardware config. Usually do not edit it manually.
- `hosts/default/packages.nix` contains system packages installed into `environment.systemPackages`.
- `modules/system.nix` contains system-wide settings: boot, networking, locale, GPU, audio, virtualization, portals, services, fonts, and security.
- `modules/user.nix` contains user-facing settings: user account, zsh, shell tools, Spicetify, browser defaults, cursor variables, and user services.
- `rebuild.sh` stages changes, rebuilds core config changes, commits them, and pushes to the configured remote.

## Common Tasks

Add or remove packages:

```bash
$EDITOR /etc/nixos/hosts/default/packages.nix
```

Change system services, hardware options, boot settings, VPN, audio, GPU, virtualization, or desktop system integration:

```bash
$EDITOR /etc/nixos/modules/system.nix
```

Change the user account, zsh aliases, shell initialization, Spicetify, browser defaults, or user services:

```bash
$EDITOR /etc/nixos/modules/user.nix
```

Change the hostname or host-level imports:

```bash
$EDITOR /etc/nixos/hosts/default/configuration.nix
```

Update flake inputs:

```bash
nix flake update /etc/nixos
```

## Rebuild

Use the local helper script:

```bash
cd /etc/nixos
./rebuild.sh
```

Or run NixOS rebuild directly:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#nixos
```

## Validate Without Switching

Evaluate the system derivation:

```bash
nix eval path:/etc/nixos#nixosConfigurations.nixos.config.system.build.toplevel.drvPath
```

Build without switching:

```bash
nix build path:/etc/nixos#nixosConfigurations.nixos.config.system.build.toplevel
```

Check the rebuild script syntax:

```bash
bash -n /etc/nixos/rebuild.sh
```

## Git Notes

Nix flakes normally evaluate tracked files from the Git tree. If you add a new file and evaluate with `--flake /etc/nixos`, make sure it is staged or committed first:

```bash
sudo git add /etc/nixos
```

For quick local checks before staging new files, use the `path:` flake form:

```bash
nix eval path:/etc/nixos#nixosConfigurations.nixos.config.system.build.toplevel.drvPath
```

## Adding More Structure

For more hosts, create another directory under `hosts/` and add another `nixosConfigurations.<name>` entry in `flake.nix`.

For reusable settings, create another file under `modules/` and import it from the host configuration.
