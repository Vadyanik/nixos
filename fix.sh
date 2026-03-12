#!/usr/bin/env bash

# Переходим в директорию с конфигами
cd /etc/nixos || exit

echo "🔍 Начинаю замену устаревших пакетов xorg..."

# Используем sed для поиска и замены во всех .nix файлах
# Флаг -i вносит изменения прямо в файлы
sed -i 's/xorg.libX11/libx11/g' *.nix
sed -i 's/xorg.libXcomposite/libxcomposite/g' *.nix
sed -i 's/xorg.libXdamage/libxdamage/g' *.nix
sed -i 's/xorg.libXrandr/libxrandr/g' *.nix
sed -i 's/xorg.libxcb/libxcb/g' *.nix
sed -i 's/xorg.libXext/libxext/g' *.nix
sed -i 's/xorg.libXfixes/libxfixes/g' *.nix

echo "✅ Замена завершена. Теперь можно запускать rebuild.sh"
