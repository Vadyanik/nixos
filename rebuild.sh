#!/usr/bin/env bash

REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# Get your actual Git identity
USER_NAME=$(sudo -u "$REAL_USER" git config --global user.name)
USER_EMAIL=$(sudo -u "$REAL_USER" git config --global user.email)

cd /etc/nixos || exit

# Use your identity, or fallback if not set
sudo git config --global --add safe.directory /etc/nixos
sudo git config user.name "${USER_NAME:-NixOS Rebuild Bot}"
sudo git config user.email "${USER_EMAIL:-rebuild-bot@nixos.local}"

if git diff --quiet && git diff --cached --quiet && \
   [ -z "$(git ls-files --others --exclude-standard)" ]; then
    echo "No changes detected. Exiting."
    exit 0
fi

sudo git add .

# Detect if core files were modified
CORE_CHANGED=$(git diff --cached --name-only | grep -E 'flake.nix|configuration.nix')

if [ -n "$CORE_CHANGED" ]; then
    echo "Core changes detected ($CORE_CHANGED). Rebuilding..."
    
    if sudo nixos-rebuild switch --flake . --quiet; then
        echo "Rebuild successful. Committing..."
        sudo git commit -m "rebuild: $(date +'%Y-%m-%d %H:%M:%S')" --quiet
        sudo GIT_SSH_COMMAND="ssh -i $USER_HOME/.ssh/id_ed25519 -o IdentitiesOnly=yes" \
             git push origin main --force
    else
        echo "Rebuild failed!"
        exit 1
    fi
else
    echo "Non-core changes detected. Syncing..."
    sudo git commit -m "update: $(date +'%Y-%m-%d %H:%M:%S')" --quiet
    sudo GIT_SSH_COMMAND="ssh -i $USER_HOME/.ssh/id_ed25519 -o IdentitiesOnly=yes" \
         git push origin main --force
fi

echo "Done."
