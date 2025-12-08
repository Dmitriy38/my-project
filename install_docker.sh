# Add Docker's official GPG key:
sudo apt update
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update

sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo systemctl status docker

sudo systemctl start docker

sudo mkdir /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "registry-mirrors": [
    "https://mirror.gr.to",
    "https://cr.yandex/mirror"
  ]
}
EOF

sudo systemctl status docker

sudo systemctl start docker
#Создание группы docker, если её нет
sudo groupadd docker 2>/dev/null || true
# Добавление текущего пользователя в группу docker
sudo usermod -aG docker $USER
# Применение изменений групп без перезагрузки (для текущей сессии)
newgrp docker << EONG
echo "Пользователь $USER добавлен в группу docker"
EONG
#запускаем тестовый контейнер приветственный 
sudo docker run hello-world