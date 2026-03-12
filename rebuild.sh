#!/usr/bin/env bash

# Detect the real user who called sudo
REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

cd /etc/nixos || exit

# Setup Git identity for this session
sudo git config --global --add safe.directory /etc/nixos
sudo git config user.email "rebuild-bot@nixos.local"
sudo git config user.name "NixOS Rebuild Bot"

# Stage changes
sudo git add .

# Handle empty repository
if ! sudo git rev-parse --verify HEAD >/dev/null 2>&1; then
    sudo git commit -m "initial commit" --quiet
fi

# Ensure main branch
sudo git branch -M main

# Commit changes if any
if ! sudo git diff-index --quiet HEAD; then
    echo "Changes detected, creating commit..."
    sudo git commit -m "rebuild: $(date +'%Y-%m-%d %H:%M:%S')" --quiet
else
    echo "No configuration changes detected."
fi

echo "Starting NixOS rebuild..."
sudo nixos-rebuild switch --flake . --quiet

if [ $? -eq 0 ]; then
    echo "System updated successfully."
    echo "Pushing changes to repository..."
    
    # Try to push using the calling user's SSH keys automatically
    if [ -f "$USER_HOME/.ssh/id_ed25519" ]; then
        sudo GIT_SSH_COMMAND="ssh -i $USER_HOME/.ssh/id_ed25519 -o IdentitiesOnly=yes" \
             git push origin main --force
    else
        # Fallback to standard push if specific key isn't found
        git push origin main --force
    fi
else
    echo "Rebuild failed."
    exit 1
fi

echo "Last commit:"
git log -1 --oneline
