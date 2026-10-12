#!/usr/bin/env bash

# 1. Первый символ теперь пробел (для уровня 0)
bar=" ▂▃▄▅▆▇█"
dict="s/;//g;"

# creating "dictionary" to replace char with bar
i=0
while [ $i -lt ${#bar} ]
do
    dict="${dict}s/$i/${bar:$i:1}/g;"
    i=$((i=i+1))
done

# write cava config
config_file="/tmp/polybar_cava_config"
echo "
[general]
bars = 116

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 7
" > $config_file

# read stdout from cava
cava -p $config_file | while read -r line; do
    # Убираем все точки с запятой
    clean_line="${line//;/}"

    # 2. Если строка состоит только из нулей (полная тишина)
    if [[ "$clean_line" =~ ^0+$ ]]; then
        echo "" # Выводим абсолютную пустоту, чтобы скрыть виджет
    else
        # Если есть звук, прогоняем через словарь
        echo "$line" | sed "$dict"
    fi
done
