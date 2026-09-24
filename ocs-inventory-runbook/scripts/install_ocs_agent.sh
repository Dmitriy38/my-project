#!/bin/bash
# Установка OCS Inventory Agent на Linux-клиент (Debian/Ubuntu).
# Запуск: sudo OCS_SERVER=http://<IP_сервера>/ocsinventory ./install_ocs_agent.sh
set -e

OCS_SERVER="${OCS_SERVER:?Укажи адрес сервера, например http://<IP_сервера>/ocsinventory}"

# Проверка: агент уже установлен?
if dpkg -l | grep -q "^ii  ocsinventory-agent"; then
    echo "OCS Agent уже установлен. Пропускаем..."
    exit 0
fi

# Обновление кэша пакетов и установка агента (без запросов)
echo "Установка OCS Agent..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ocsinventory-agent

# Адрес сервера
echo "Настройка конфигурации..."
echo "server=${OCS_SERVER}" > /etc/ocsinventory/ocsinventory-agent.cfg

# Первый запуск инвентаризации
echo "Запуск инвентаризации..."
ocsinventory-agent

echo "Готово!"
