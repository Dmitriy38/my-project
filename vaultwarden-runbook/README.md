# Vaultwarden: корпоративный менеджер паролей с нуля

Runbook по развёртыванию self-hosted менеджера паролей Vaultwarden в закрытой корпоративной сети: за reverse proxy, с локальным SSL-сертификатом, внутренним DNS и изоляцией контейнеров файрволом.

## Стек

- Ubuntu Server, Docker, Docker Compose
- Vaultwarden (совместим с клиентами Bitwarden)
- Nginx Proxy Manager + MariaDB
- UFW + цепочка `DOCKER-USER`
- Active Directory DNS
- OpenSSL (самоподписанный сертификат с SAN)
- Hyper-V (виртуализация)

## Схема

```
Клиент (Windows / Android / iOS)
        │  https://bitwarden.yourdomain.local
        ▼
   AD DNS (A-запись)  →  10.X.X.X
        ▼
   Nginx Proxy Manager (:443, SSL)
        ▼
   Vaultwarden (:8085)  ←→  SMTP (инвайты)
```

Доступ к серверу открыт только из корпоративной подсети.

## Содержание

1. [Установка Docker и Docker Compose](#шаг-1-установка-docker-и-docker-compose)
2. [Настройка Firewall (UFW и изоляция Docker)](#шаг-2-настройка-firewall-ufw-и-изоляция-docker)
3. [Файлы конфигурации Docker Compose](#шаг-3-файлы-конфигурации-docker-compose)
4. [Корпоративный DNS](#шаг-4-корпоративный-dns)
5. [Локальный SSL-сертификат](#шаг-5-генерация-локального-ssl-сертификата)
6. [Настройка Nginx Proxy Manager](#шаг-6-настройка-nginx-proxy-manager)
7. [Доверие сертификату на устройствах](#шаг-7-установка-доверия-на-устройствах)
8. [Настройка админ-панели (SMTP)](#шаг-8-завершение-настройки-в-админ-панели-smtp)
9. [Траблшутинг: проблемы с отправкой почты](#шаг-9-траблшутинг-отправка-почты-smtp)

> В примерах `10.X.X.X`, `yourdomain.local`, `YOUR_*_PASSWORD` это плейсхолдеры. Подставь свои значения.

---

## Шаг 1. Установка Docker и Docker Compose

Предполагается, что на сервере стоит базовая Ubuntu Server.

Обновление пакетов и установка Docker:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y docker.io docker-compose-v2
```

Автозапуск Docker при загрузке:

```bash
sudo systemctl enable --now docker
```

---

## Шаг 2. Настройка Firewall (UFW и изоляция Docker)

Разрешаем доступ только из корпоративной подсети (например, `10.X.X.0/16`):

```bash
sudo ufw allow from 10.X.X.0/16
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable
```

Docker игнорирует стандартные правила UFW, поэтому ограничиваем доступ к контейнерам через цепочку `DOCKER-USER`. Открой файл:

```bash
sudo nano /etc/ufw/after.rules
```

Добавь в самый конец (замени `eth0` на имя своего интерфейса, если оно другое):

```
# Настройка DOCKER-USER для ограничения доступа к контейнерам
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -i eth0 ! -s 10.X.X.0/16 -j DROP
-A DOCKER-USER -j RETURN
COMMIT
```

Применить правила:

```bash
sudo ufw reload
```

---

## Шаг 3. Файлы конфигурации Docker Compose

Рабочие директории в `/opt`:

```bash
sudo mkdir -p /opt/vaultwarden /opt/npm
```

### 3.1. Nginx Proxy Manager с БД MariaDB

Файл `/opt/npm/docker-compose.yml`:

```yaml
services:
  app:
    image: 'jc21/nginx-proxy-manager:2.15.1'
    restart: unless-stopped
    ports:
      - '80:80'
      - '443:443'
      - '81:81'
    environment:
      TZ: "Europe/Moscow"
      DB_MYSQL_HOST: "db"
      DB_MYSQL_PORT: 3306
      DB_MYSQL_USER: "nginx-pm"
      DB_MYSQL_PASSWORD: "YOUR_DB_PASSWORD"
      DB_MYSQL_NAME: "npm"
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    depends_on:
      - db

  db:
    image: 'linuxserver/mariadb'
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: 'YOUR_ROOT_PASSWORD'
      MYSQL_DATABASE: 'npm'
      MYSQL_USER: 'nginx-pm'
      MYSQL_PASSWORD: 'YOUR_DB_PASSWORD'
      TZ: 'Europe/Moscow'
    volumes:
      - ./data/mariadb:/config
```

### 3.2. Vaultwarden

Файл `/opt/vaultwarden/docker-compose.yml`:

```yaml
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: always
    environment:
      - WEBSOCKET_ENABLED=true
      - SIGNUPS_ALLOWED=false
      # Пароль админа хранится как хэш Argon2, символы $ экранируются как $$
      - ADMIN_TOKEN=$$argon2id$$v=19$$m=65536,t=3,p=4$$R3...
      - DOMAIN=https://bitwarden.yourdomain.local
      # Настройки SMTP для отправки инвайтов
      - SMTP_HOST=mail.yourdomain.ru
      - SMTP_FROM=bitwarden@yourdomain.ru
      - SMTP_PORT=465
      - SMTP_SECURITY=force_tls
      - SMTP_USERNAME=bitwarden@yourdomain.ru
      - SMTP_PASSWORD=YOUR_PASSWORD
    volumes:
      - ./vw-data:/data
    ports:
      - 0.0.0.0:8085:80
```

**Как получить `ADMIN_TOKEN` (Argon2):**

1. Запусти контейнер Vaultwarden.
2. Выполни: `sudo docker exec -it vaultwarden /vaultwarden hash`
3. Введи придуманный пароль админа.
4. Скопируй полученный хэш, замени в нём каждый `$` на `$$` (экранирование в YAML) и вставь в конфиг.

### 3.3. Запуск

По очереди в каждой папке:

```bash
cd /opt/npm && sudo docker compose up -d
cd /opt/vaultwarden && sudo docker compose up -d
```

---

## Шаг 4. Корпоративный DNS

1. На контроллере домена AD открой диспетчер DNS.
2. В зоне `yourdomain.local` создай A-запись:
   - Имя: `bitwarden`
   - IP-адрес: `10.X.X.X` (IP сервера с Docker)

---

## Шаг 5. Генерация локального SSL-сертификата

Мобильные клиенты требуют поле SAN в сертификате. Выполни на сервере Ubuntu:

```bash
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout bitwarden.key -out bitwarden.crt \
  -subj "/CN=bitwarden.yourdomain.local" \
  -addext "subjectAltName=DNS:bitwarden.yourdomain.local"
```

Скопируй `bitwarden.crt` и `bitwarden.key` на рабочий ПК.

---

## Шаг 6. Настройка Nginx Proxy Manager

1. Открой панель NPM: `http://10.X.X.X:81`.
2. **SSL Certificates → Add Custom Certificate**: загрузи `bitwarden.crt` и `bitwarden.key`.
3. Создай **Proxy Host**:
   - Domain: `bitwarden.yourdomain.local`
   - Forward IP: `10.X.X.X`, Port: `8085`
   - включи **WebSockets Support**
4. На вкладке **SSL** выбери загруженный сертификат и включи **Force SSL**.

---

## Шаг 7. Установка доверия на устройствах

- **Windows:** импортировать `bitwarden.crt` в хранилище «Доверенные корневые центры сертификации».
- **Android / iOS:** скачать сертификат и установить как доверенный CA (настройки безопасности системы). На iOS дополнительно включить доверие: «Основные → Об этом устройстве → Доверие сертификатам».

---

## Шаг 8. Завершение настройки в админ-панели (SMTP)

Переменные `SMTP` и `DOMAIN` из `docker-compose.yml` могут игнорироваться, если они переопределены в веб-интерфейсе админки (при этом создаётся файл `config.json`). Чтобы ссылки в инвайтах работали, закрепи настройки в панели:

1. Открой `https://bitwarden.yourdomain.local/admin`.
2. **General settings → Domain URL**: впиши `https://bitwarden.yourdomain.local` и нажми **Save**.
3. Раздел **SMTP**: проверь настройки почты. Если почтовый сервер указан по IP-адресу, включи внизу **Accept Invalid Certs** и **Accept Invalid Hostnames**.

---

## Шаг 9. Траблшутинг: отправка почты (SMTP)

**Симптом:** при тестовой отправке ошибка `SMTP timeout error: Connection error: connection timed out`, а пакеты зависают в статусе `syn received`.

### Проблема 1. Аппаратная выгрузка контрольных сумм в Hyper-V

Если сервер работает на Hyper-V, виртуальный сетевой адаптер может неверно считать контрольные суммы TCP. Ядро Linux считает входящие SYN-ACK от почтового сервера повреждёнными и отбрасывает их.

**Решение:** отключить offloading на интерфейсе (в примере `eth0`).

```bash
sudo apt update && sudo apt install ethtool -y
sudo ethtool -K eth0 tx off rx off
```

Чтобы настройка пережила перезагрузку, добавь команду в автозагрузку, например через `crontab @reboot`.

### Проблема 2. Конфликт маршрутизации UFW и Docker

При `ufw reload` или перезагрузке файрвол пересобирает таблицы и стирает правила переадресации (`FORWARD`) Docker. Ответный трафик из интернета перестаёт доходить до контейнеров.

**Решение:** добавить в цепочку `DOCKER-USER` правило, которое пропускает ответы на установленные соединения.

1. Открой файл:

   ```bash
   sudo nano /etc/ufw/after.rules
   ```

2. Внизу, после `COMMIT`, добавь блок:

   ```
   # Разрешаем входящие ответы от серверов для Docker-контейнеров
   *filter
   :DOCKER-USER - [0:0]
   -I DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
   -A DOCKER-USER -j RETURN
   COMMIT
   ```

3. Применить правила и перезапустить Docker, чтобы он пересобрал сетевые мосты:

   ```bash
   sudo ufw reload
   sudo systemctl restart docker
   ```
