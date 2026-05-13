#!/usr/bin/env bash

# --- Configuration ---
PROFILE_REPO_PATH="/home/vadyanik/dev/Vadyanik"
BIRTH_DATE="2026-02-13"
# -------------------

REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

export LC_ALL=C

# Generate a commit message with AI or a timestamp fallback.
generate_commit_message() {
    local prefix="$1"  # "rebuild" or "update"
    local fallback_msg="${prefix}: $(date +'%Y-%m-%d %H:%M:%S')"

    local ai_msg
    local ai_error
    local temp_error_file=$(mktemp)

    ai_msg=$(sudo -u "$REAL_USER" /home/vadyanik/.local/bin/aic -p 2>"$temp_error_file" || echo "")
    ai_error=$(cat "$temp_error_file")
    rm -f "$temp_error_file"

    if [ -n "$ai_msg" ] && [ "$ai_msg" != "" ]; then
        echo "$ai_msg"
    else
        if [ -n "$ai_error" ]; then
            echo -e "\n\e[1;31m✗ AI commit failed:\e[0m" >&2
            echo -e "\e[31m$ai_error\e[0m\n" >&2
        fi
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

CORE_CHANGED=$(git diff --cached --name-only | grep -E '^(flake\.nix|flake\.lock|hosts/|modules/)')

if [ -n "$CORE_CHANGED" ]; then
    echo "Core changes detected. Rebuilding..."

    if sudo nixos-rebuild switch --flake . --quiet; then
        echo "Rebuild successful. Calculating stats..."

        if [ -d "$PROFILE_REPO_PATH" ]; then
            README_FILE="$PROFILE_REPO_PATH/README.md"
            pushd "$PROFILE_REPO_PATH" > /dev/null

            sudo -u "$REAL_USER" git pull origin main --quiet

            CURRENT_COUNT=$(grep -oP 'System%20Rebuilds-\K[0-9]+' "$README_FILE" | head -n 1)
            [ -z "$CURRENT_COUNT" ] && CURRENT_COUNT=0
            NEW_COUNT=$((CURRENT_COUNT + 1))

            TODAY=$(date +%s)
            START=$(date -d "$BIRTH_DATE" +%s)
            DIFF_DAYS=$(( (TODAY - START) / 86400 ))
            [ "$DIFF_DAYS" -lt 1 ] && DIFF_DAYS=1

            AVG_REBUILDS=$(echo "scale=2; $NEW_COUNT / $DIFF_DAYS" | bc | awk '{printf "%.2f", $0}')

            LAST_REBUILD_TIME=$(date +'%d.%m.%Y%%20%H:%M')

            sed -i "s|^!\[Rebuilds\].*|![Rebuilds](https://img.shields.io/badge/System%20Rebuilds-${NEW_COUNT}-blue?style=flat-square\&logo=nixos)|" "$README_FILE"

            sed -i "s|^!\[Rebuilds Per Day\].*|![Rebuilds Per Day](https://img.shields.io/badge/Avg%20Rebuilds%2FDay-${AVG_REBUILDS}-orange?style=flat-square)|" "$README_FILE"

            sed -i "s|^!\[Last Rebuild\].*|![Last Rebuild](https://img.shields.io/badge/Last%20Update-${LAST_REBUILD_TIME}-blue?style=flat-square)|" "$README_FILE"

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
        if [[ "$COMMIT_MSG" =~ ^rebuild:\ [0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
            echo -e "\n\e[1;36mAuto Commit:\e[0m \e[1;32m$COMMIT_MSG\e[0m\n"
        else
            echo -e "\n\e[1;36mAI Commit:\e[0m \e[1;32m$COMMIT_MSG\e[0m\n"
        fi
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
    if [[ "$COMMIT_MSG" =~ ^update:\ [0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
        echo -e "\n\e[1;36mAuto Commit:\e[0m \e[1;32m$COMMIT_MSG\e[0m\n"
    else
        echo -e "\n\e[1;36mAI Commit:\e[0m \e[1;32m$COMMIT_MSG\e[0m\n"
    fi
    sudo GIT_SSH_COMMAND="ssh -i $USER_HOME/.ssh/id_ed25519 -o IdentitiesOnly=yes" \
         git push origin main --force
fi

echo "Done."
