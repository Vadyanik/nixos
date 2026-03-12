#!/usr/bin/env bash

PROFILE_REPO_PATH="/home/vadyanik/dev/Vadyanik"

REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# Get your actual Git identity
USER_NAME=$(sudo -u "$REAL_USER" git config --global user.name)
USER_EMAIL=$(sudo -u "$REAL_USER" git config --global user.email)

cd /etc/nixos || exit

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
        echo "Rebuild successful. Updating counter..."
        
        if [ -d "$PROFILE_REPO_PATH" ]; then
            README_FILE="$PROFILE_REPO_PATH/README.md"
            # Извлекаем текущее число из бейджа, увеличиваем на 1
            CURRENT_COUNT=$(grep -oP 'System%20Rebuilds-\K[0-9]+' "$README_FILE")
            NEW_COUNT=$((CURRENT_COUNT + 1))
            
            # Заменяем старое число на новое в файле
            sed -i "s/System%20Rebuilds-$CURRENT_COUNT/System%20Rebuilds-$NEW_COUNT/" "$README_FILE"
            
            # Пушим изменения в репозиторий профиля
            pushd "$PROFILE_REPO_PATH" > /dev/null
            git add README.md
            git commit -m "profile: update rebuild counter to $NEW_COUNT" --quiet
            sudo GIT_SSH_COMMAND="ssh -i $USER_HOME/.ssh/id_ed25519 -o IdentitiesOnly=yes" \
                 git push origin main --quiet
            popd > /dev/null
            echo "Counter updated to $NEW_COUNT."
        else
            echo "Warning: Profile repo path not found at $PROFILE_REPO_PATH"
        fi

        echo "Committing nixos config..."
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
