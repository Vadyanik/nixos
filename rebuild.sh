#!/usr/bin/env bash

cd /etc/nixos || exit

# 1. Настраиваем "личность" для root в этой папке, если не задано
sudo git config user.email "root@nixos.local"
sudo git config user.name "NixOS Rebuild Bot"
sudo git config --global --add safe.directory /etc/nixos

# 2. Добавляем файлы
sudo git add .

# 3. Инициализируем первый коммит, если репозиторий пустой (исправляет ошибку HEAD)
if ! sudo git rev-parse --verify HEAD >/dev/null 2>&1; then
    sudo git commit -m "initial commit" --quiet
fi

# 4. Делаем коммит изменений, чтобы скрыть ворнинг "dirty tree"
if ! sudo git diff-index --quiet HEAD; then
    sudo git commit -m "rebuild: $(date +'%Y-%m-%d %H:%M:%S')" --quiet
fi

echo "🚀 Начинаю тихую пересборку NixOS..."

# 5. Сама пересборка
sudo nixos-rebuild switch --flake . --quiet

if [ $? -eq 0 ]; then
    echo "✅ Система успешно обновлена и зафиксирована в Git!"
else
    echo "❌ Ошибка при пересборке."
    exit 1
fi
