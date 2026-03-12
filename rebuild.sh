#!/usr/bin/env bash

cd /etc/nixos || exit

# 1. Настраиваем "личность" для root в этой папке, если не задано
sudo git config user.email "root@nixos.local"
sudo git config user.name "NixOS Rebuild Bot"
sudo git config --global --add safe.directory /etc/nixos

# 2. Добавляем файлы
sudo git add .

# 4. Делаем коммит изменений, чтобы скрыть ворнинг "dirty tree"

if ! sudo git diff-index --quiet HEAD; then
    echo "📝 Обнаружены изменения, создаю коммит..."
    sudo git commit -m "rebuild: $(date +'%Y-%m-%d %H:%M:%S')"
else
    echo "☕ Изменений в конфигурации нет, пропускаю коммит."
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

# Добавьте это в конец скрипта
echo "📊 Последний коммит в истории:"
git log -1 --oneline
