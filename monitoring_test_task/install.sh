#!/bin/bash

set -e

echo "Установка системы мониторинга для процесса test"

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo "Пожалуйста, запустите скрипт с правами root (sudo)"
    exit 1
fi

# Создание необходимых директорий
echo "Создание директорий"
mkdir -p /usr/local/bin
mkdir -p /etc/systemd/system

# Копирование скрипта
echo "Копирование скрипта мониторинга"
cp monitoring.sh /usr/local/bin/monitoring.sh
chmod +x /usr/local/bin/monitoring.sh

# Копирование systemd файлов
echo "Настройка systemd служб"
cp monitoring.service /etc/systemd/system/
cp monitoring.timer /etc/systemd/system/

# Создание лог-файла
echo "Создание лог-файла"
touch /var/log/monitoring.log
chmod 644 /var/log/monitoring.log

# Перезагрузка systemd
echo "Перезагрузка systemd"
systemctl daemon-reload

# Включение и запуск таймера
echo "Запуск службы мониторинга"
systemctl enable monitoring.timer
systemctl start monitoring.timer

echo "Установка завершена!"
echo "Статус можно проверить командой: systemctl status monitoring.timer"
echo "Логи будут записываться в: /var/log/monitoring.log"
