#!/usr/bin/env bash

# --- CONFIGURATION ---
PROFILE_REPO_PATH="/home/vadyanik/dev/Vadyanik"
BIRTH_DATE="2026-02-13" # Твой первый ребилд
# ---------------------

REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# Настройка Git для работы от имени пользователя
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

CORE_CHANGED=$(git diff --cached --name-only | grep -E 'flake.nix|configuration.nix')

if [ -n "$CORE_CHANGED" ]; then
    echo "Core changes detected. Rebuilding..."

    if sudo nixos-rebuild switch --flake . --quiet; then
        echo "Rebuild successful. Calculating stats..."

        if [ -d "$PROFILE_REPO_PATH" ]; then
                    README_FILE="$PROFILE_REPO_PATH/README.md"

                    # Все операции с Git внутри профиля делаем от имени пользователя
                    pushd "$PROFILE_REPO_PATH" > /dev/null

                    # Синхронизация
                    sudo -u "$REAL_USER" git pull origin main --quiet

                    # 1. Считаем общее количество
                    CURRENT_COUNT=$(grep -oP 'System%20Rebuilds-\K[0-9]+' "$README_FILE")
                    [ -z "$CURRENT_COUNT" ] && CURRENT_COUNT=0
                    NEW_COUNT=$((CURRENT_COUNT + 1))

                    # 2. Считаем среднее
                                TODAY=$(date +%s)
                                START=$(date -d "$BIRTH_DATE" +%s)
                                DIFF_DAYS=$(( (TODAY - START) / 86400 ))
                                [ "$DIFF_DAYS" -lt 1 ] && DIFF_DAYS=1

                                if command -v bc >/dev/null 2>&1; then
                                    RAW_AVG=$(echo "scale=1; $NEW_COUNT / $DIFF_DAYS" | bc)
                                    # Красивое форматирование: превращаем .9 в 0.9
                                    AVG_REBUILDS=$(printf "%.1f" "$RAW_AVG")
                                else
                                    AVG_REBUILDS="0.0"
                                fi

                                # 3. Время последнего ребилда
                                LAST_REBUILD_TIME=$(date +'%Y--%m--%d%20%H:%M')

                                # 4. Обновляем README с помощью awk (никакого Python и Perl)
                                awk -v count="$NEW_COUNT" -v avg="$AVG_REBUILDS" -v time="$LAST_REBUILD_TIME" '
                                // {
                                    print ""
                                    print "![Rebuilds](https://img.shields.io/badge/System%20Rebuilds-" count "-blue?style=flat-square&logo=nixos)"
                                    print "![Rebuilds Per Day](https://img.shields.io/badge/Avg%20Rebuilds%2FDay-" avg "-orange?style=flat-square)"
                                    print "![Last Rebuild](https://img.shields.io/badge/Last%20Rebuild-" time "-green?style=flat-square)"
                                    print ""
                                    skip = 1
                                    next
                                }
                                // {
                                    skip = 0
                                    next
                                }
                                !skip { print }
                                ' "$README_FILE" > "${README_FILE}.tmp"

                                # Возвращаем файл на место и исправляем права
                                mv "${README_FILE}.tmp" "$README_FILE"
                                chown "$REAL_USER:users" "$README_FILE"

                                # Пушим в профиль
                                sudo -u "$REAL_USER" git add README.md
                                sudo -u "$REAL_USER" git commit -m "profile: rebuild #$NEW_COUNT ($AVG_REBUILDS/day)" --quiet
                                sudo -u "$REAL_USER" GIT_SSH_COMMAND="ssh -i $USER_HOME/.ssh/id_ed25519 -o IdentitiesOnly=yes" \
                                     git push origin main --quiet


                    popd > /dev/null
                    echo "Stats updated: Total $NEW_COUNT, Avg $AVG_REBUILDS/day"
            fi

        # Коммит самого конфига
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
