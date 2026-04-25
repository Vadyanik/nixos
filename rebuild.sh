#!/usr/bin/env bash

# --- CONFIGURATION ---
PROFILE_REPO_PATH="/home/vadyanik/dev/Vadyanik"
BIRTH_DATE="2026-02-13"
# ---------------------

REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

export LC_ALL=C

# Function to generate commit message with AI or fallback
generate_commit_message() {
    local prefix="$1"  # "rebuild" or "update"
    local fallback_msg="${prefix}: $(date +'%Y-%m-%d %H:%M:%S')"

    # Try to get AI-generated message
    echo "[DEBUG] Attempting to run: sudo -u $REAL_USER /home/vadyanik/.local/bin/aic -y" >&2
    local ai_msg
    ai_msg=$(sudo -u "$REAL_USER" /home/vadyanik/.local/bin/aic -y)
    local exit_code=$?

    echo "[DEBUG] aic exit code: $exit_code" >&2
    echo "[DEBUG] aic output: '$ai_msg'" >&2
    echo "[DEBUG] aic output length: ${#ai_msg}" >&2

    # Use AI message if non-empty, otherwise fallback
    if [ -n "$ai_msg" ] && [ "$ai_msg" != "" ]; then
        echo "$ai_msg"
    else
        echo "[DEBUG] Using fallback message" >&2
        echo "$fallback_msg"
    fi
}

cd /etc/nixos || exit

sudo git config --global --add safe.directory /etc/nixos
USER_NAME=$(sudo -u "$REAL_USER" git config --global user.name)
USER_EMAIL=$(sudo -u "$REAL_USER" git config --global user.email)
sudo git config user.name "${USER_NAME:-NixOS Rebuild Bot}"
sudo git config user.email "${USER_EMAIL:-rebuild-bot@nixos.local}"

if git diff --quiet && git diff --cached --quiet && \
   [ -z "$(git ls-files --others --exclude-standard)" ]; then
    echo "No changes detected. Exiting."
    exit 0
fi

sudo git add .

CORE_CHANGED=$(git diff --cached --name-only | grep -E 'flake.nix|configuration.nix')

if [ -n "$CORE_CHANGED" ]; then
    echo "Core changes detected. Rebuilding..."

    if sudo nixos-rebuild switch --flake . --quiet; then
        echo "Rebuild successful. Calculating stats..."

        if [ -d "$PROFILE_REPO_PATH" ]; then
            README_FILE="$PROFILE_REPO_PATH/README.md"
            pushd "$PROFILE_REPO_PATH" > /dev/null

            sudo -u "$REAL_USER" git pull origin main --quiet

            # 1. Считаем общее количество
            CURRENT_COUNT=$(grep -oP 'System%20Rebuilds-\K[0-9]+' "$README_FILE" | head -n 1)
            [ -z "$CURRENT_COUNT" ] && CURRENT_COUNT=0
            NEW_COUNT=$((CURRENT_COUNT + 1))

            # 2. Считаем среднее (теперь с точностью до 2 знаков)
            TODAY=$(date +%s)
            START=$(date -d "$BIRTH_DATE" +%s)
            DIFF_DAYS=$(( (TODAY - START) / 86400 ))
            [ "$DIFF_DAYS" -lt 1 ] && DIFF_DAYS=1

            AVG_REBUILDS=$(echo "scale=2; $NEW_COUNT / $DIFF_DAYS" | bc | awk '{printf "%.2f", $0}')

            # 3. Время (Новый формат: День.Месяц.Год Время)
            LAST_REBUILD_TIME=$(date +'%d.%m.%Y%%20%H:%M')

            # 4. Обновляем README точечно через sed
            sed -i "s|^!\[Rebuilds\].*|![Rebuilds](https://img.shields.io/badge/System%20Rebuilds-${NEW_COUNT}-blue?style=flat-square\&logo=nixos)|" "$README_FILE"

            sed -i "s|^!\[Rebuilds Per Day\].*|![Rebuilds Per Day](https://img.shields.io/badge/Avg%20Rebuilds%2FDay-${AVG_REBUILDS}-orange?style=flat-square)|" "$README_FILE"

            sed -i "s|^!\[Last Rebuild\].*|![Last Rebuild](https://img.shields.io/badge/Last%20Update-${LAST_REBUILD_TIME}-blue?style=flat-square)|" "$README_FILE"

            # Возвращаем права владельцу
            chown "$REAL_USER:users" "$README_FILE"

            sudo -u "$REAL_USER" git add README.md
            sudo -u "$REAL_USER" git commit -m "profile: rebuild #$NEW_COUNT ($AVG_REBUILDS/day)" --quiet
            sudo -u "$REAL_USER" GIT_SSH_COMMAND="ssh -i $USER_HOME/.ssh/id_ed25519 -o IdentitiesOnly=yes" \
                 git push origin main --quiet

            popd > /dev/null
            echo "Stats updated: Total $NEW_COUNT, Avg $AVG_REBUILDS/day"
        fi

        COMMIT_MSG=$(generate_commit_message "rebuild")
        sudo git commit -m "$COMMIT_MSG" --quiet
        sudo GIT_SSH_COMMAND="ssh -i $USER_HOME/.ssh/id_ed25519 -o IdentitiesOnly=yes" \
             git push origin main --force
    else
        echo "Rebuild failed!"
        exit 1
    fi
else
    echo "Non-core changes detected. Syncing..."
    COMMIT_MSG=$(generate_commit_message "update")
    sudo git commit -m "$COMMIT_MSG" --quiet
    sudo GIT_SSH_COMMAND="ssh -i $USER_HOME/.ssh/id_ed25519 -o IdentitiesOnly=yes" \
         git push origin main --force
fi

echo "Done."
