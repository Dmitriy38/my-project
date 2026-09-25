#!/bin/bash

# 1. Удаление старых конфликтующих пакетов (на всякий случай)
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove -y $pkg; done

# 2. Установка базовых зависимостей
sudo apt-get update
sudo apt-get install -y ca-certificates curl

# 3. Создание директории для ключей и скачивание официального GPG-ключа Docker
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# 4. Добавление репозитория Docker в источники APT
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 5. Обновление индексов пакетов и установка Docker
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 6. Добавление текущего пользователя в группу docker (чтобы не использовать sudo docker)
if ! getent group docker > /dev/null; then
    sudo groupadd docker
fi
sudo usermod -aG docker $USER

# 7. Включение автозапуска службы
sudo systemctl enable docker
sudo systemctl start docker

echo "Установка завершена! Выйдите из системы (logout) и зайдите снова, чтобы применились права группы docker."
