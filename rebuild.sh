#!/usr/bin/env bash

# Setup environment
REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
cd /etc/nixos || exit

# Git hygiene
sudo git config --global --add safe.directory /etc/nixos
sudo git config user.email "rebuild-bot@nixos.local"
sudo git config user.name "NixOS Rebuild Bot"

# Check for any changes in the directory
if git diff --quiet && git diff --cached --quiet && \
   [ -z "$(git ls-files --others --exclude-standard)" ]; then
    echo "No changes detected at all. Exiting."
    exit 0
fi

# 1. Always stage everything first (Flakes need this to see files)
sudo git add .

# 2. Check if core files were modified
# (Detects changes in staged files)
CORE_CHANGED=$(git diff --cached --name-only | grep -E 'flake.nix|configuration.nix')

if [ -n "$CORE_CHANGED" ]; then
    echo "Core configuration changes detected ($CORE_CHANGED)."
    echo "Starting NixOS rebuild..."
    
    if sudo nixos-rebuild switch --flake . --quiet; then
        echo "Rebuild successful. Committing and pushing..."
        sudo git commit -m "rebuild: $(date +'%Y-%m-%d %H:%M:%S')" --quiet
        sudo GIT_SSH_COMMAND="ssh -i $USER_HOME/.ssh/id_ed25519 -o IdentitiesOnly=yes" \
             git push origin main --force
    else
        echo "Rebuild failed! Changes stayed staged but not committed."
        exit 1
    fi
else
    echo "No core changes detected. Syncing other files..."
    sudo git commit -m "update: non-core files $(date +'%Y-%m-%d %H:%M:%S')" --quiet
    sudo GIT_SSH_COMMAND="ssh -i $USER_HOME/.ssh/id_ed25519 -o IdentitiesOnly=yes" \
         git push origin main --force
fi

echo "Done."
