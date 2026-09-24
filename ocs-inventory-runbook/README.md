# OCS Inventory NG: сервер с нуля + сбор данных по SNMP

Runbook по развёртыванию системы инвентаризации OCS Inventory NG на Ubuntu Server: сервер (Apache + MariaDB + PHP + Perl), сбор данных с сетевых устройств (принтеры и т.п.) по SNMP через агент в Docker и мониторинг самого сервера в Zabbix.

## Стек

- Ubuntu Server 24.04, Apache 2 (mod_perl), MariaDB, PHP 8.3
- OCS Inventory NG Server 2.12.5 (установка из исходников)
- OCS Inventory Unix Agent 2.10.5 в Docker (SNMP-сканирование)
- snmp / snmp-mibs-downloader, nmap
- Zabbix Agent 2 (репозиторий Zabbix 7.0)

## Схема

```
Устройства по SNMP (принтеры, сетевое оборудование)
            │  SNMP (UDP 161)
            ▼
   Docker: ocs-snmp-agent  (network host)
            │  HTTP
            ▼
   Apache + mod_perl: OCS Inventory Server  ←→  MariaDB (ocsweb)
            ▲
            │  веб-интерфейс /ocsreports
         Администратор

   Zabbix Agent 2  →  Zabbix Server (мониторинг самого сервера)
```

## Содержание

1. [Подготовка ОС](#шаг-1-подготовка-ос)
2. [Apache, MariaDB, PHP](#шаг-2-apache-mariadb-php)
3. [Зависимости для сборки](#шаг-3-зависимости-для-установки-из-исходников)
4. [Установка сервера OCS](#шаг-4-установка-сервера-ocs-из-исходников)
5. [БД и пароли](#шаг-5-база-данных-и-мастер-установки)
6. [Связка Apache и БД](#шаг-6-связка-apache-и-бд)
7. [SNMP и MIB-файлы](#шаг-7-snmp-и-mib-файлы)
8. [SNMP-агент в Docker](#шаг-8-snmp-агент-в-docker)
9. [Zabbix Agent 2](#шаг-9-мониторинг-сервера-zabbix-agent-2)
10. [Траблшутинг](#шаг-10-траблшутинг)

> `<IP_сервера>`, `<IP_устройства>`, `YOUR_DB_PASSWORD` это плейсхолдеры. Подставь свои значения. Пароли не используй по умолчанию.

---

## Шаг 1. Подготовка ОС

```bash
sudo apt update && sudo apt upgrade -y
sudo systemctl enable --now ssh
sudo timedatectl set-timezone Asia/Irkutsk    # свой часовой пояс
sudo reboot
```

Узнать IP сервера: `ip a`.

---

## Шаг 2. Apache, MariaDB, PHP

```bash
sudo apt install apache2 mariadb-server php php-mysql php-xml php-curl php-gd php-mbstring php-soap -y
```

Лимит памяти PHP: в `/etc/php/8.3/apache2/php.ini` изменён параметр

```ini
memory_limit = -1
```

Перезапусти Apache:

```bash
sudo systemctl restart apache2
```

Часовой пояс в MariaDB: сначала загрузить таблицы часовых поясов, затем в секцию `[mysqld]` файла `/etc/mysql/mariadb.conf.d/50-server.cnf` добавить строку `default-time-zone = 'Asia/Irkutsk'` (свой пояс) и перезапустить службу. Порядок важен: пока таблицы не загружены, MariaDB не распознаёт имя пояса.

```bash
mysql_tzinfo_to_sql /usr/share/zoneinfo | sudo mysql -u root mysql
sudo nano /etc/mysql/mariadb.conf.d/50-server.cnf   # [mysqld] → default-time-zone = 'Asia/Irkutsk'
sudo systemctl restart mariadb
```

Если на сервере включён UFW, открой веб-порт только для внутренней подсети (агенты и администраторы ходят по HTTP):

```bash
sudo ufw allow from <подсеть>/<маска> to any port 80 proto tcp
```

---

## Шаг 3. Зависимости для установки из исходников

```bash
sudo apt install git make gcc perl libapache2-mod-perl2 libxml-simple-perl libdbi-perl \
  libdbd-mysql-perl libnet-ip-perl libsoap-lite-perl libarchive-zip-perl libswitch-perl \
  libxml-libxml-perl libmojolicious-perl libplack-perl libapache-dbi-perl -y
```

`libmojolicious-perl` и `libplack-perl` понадобились установщику `setup.sh`: без них он останавливается с сообщением о недостающем Perl-модуле.

---

## Шаг 4. Установка сервера OCS из исходников

Скачай архив релиза `OCSNG_UNIX_SERVER-2.12.5.tar.gz` с GitHub проекта OCSInventory-NG и распакуй:

```bash
tar -zxvf OCSNG_UNIX_SERVER-2.12.5.tar.gz
cd OCSNG_UNIX_SERVER-2.12.5
sudo ./setup.sh
```

Установщик интерактивный. Если он просит доустановить Perl-модуль, поставь пакет и запусти `setup.sh` снова.

Все параметры установки оставлены по умолчанию (об этом говорит файл `setup.answers` в папке дистрибутива):

- БД: хост `localhost`, порт `3306`, пользователь `ocs`, пароль `ocs`
- веб-интерфейс: `/usr/share/ocsinventory-reports`, доступен по адресу `/ocsreports`
- данные веб-интерфейса: `/var/lib/ocsinventory-reports`
- логи сервера: `/var/log/ocsinventory-server`
- конфигурации Apache: `ocsinventory-server.conf` (сервер приёма данных), `ocsinventory-reports.conf` (веб-интерфейс), `ocsinventory-restapi.conf` (REST API)

Пароль `ocs` по умолчанию записывается в конфигурацию Apache, поэтому после установки его нужно сменить (шаг 6).

После установки включи конфигурацию веб-интерфейса и выдай права Apache:

```bash
sudo systemctl restart apache2
sudo a2enconf ocsinventory-reports
sudo systemctl reload apache2
sudo chown -R www-data:www-data /var/lib/ocsinventory-reports
```

---

## Шаг 5. База данных и мастер установки

Создай пользователя БД для OCS. Пароль сначала `ocs`, как в установщике по умолчанию (в шаге 6 он меняется на свой):

```bash
sudo mysql -e "CREATE USER IF NOT EXISTS 'ocs'@'localhost' IDENTIFIED BY 'ocs'; \
GRANT ALL PRIVILEGES ON ocsweb.* TO 'ocs'@'localhost'; FLUSH PRIVILEGES;"
```

Мастеру установки в веб-интерфейсе нужен доступ к MariaDB. По умолчанию `root` входит только через unix-сокет, поэтому на время установки ему задаётся пароль:

```bash
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'YOUR_ROOT_PASSWORD'; FLUSH PRIVILEGES;"
```

Открой `http://<IP_сервера>/ocsreports` и пройди мастер установки (создаётся БД `ocsweb`). Первый вход: логин `admin`, пароль `admin`. Сразу смени пароль в веб-интерфейсе (Configuration → Users). После завершения мастера **обязательно удали установочный файл**:

```bash
sudo rm /usr/share/ocsinventory-reports/ocsreports/install.php
```

---

## Шаг 6. Связка Apache и БД

Пароль пользователя `ocs` должен совпадать в **двух** местах:

1. Веб-интерфейс: `/usr/share/ocsinventory-reports/ocsreports/dbconfig.inc.php`
2. Сервер приёма данных: `/etc/apache2/conf-available/z-ocsinventory-server.conf` (строки `PerlSetEnv OCS_DB_USER` и `PerlSetEnv OCS_DB_PWD`)

Порядок смены пароля с дефолтного `ocs`:

1. Сменить пароль в БД:

```bash
sudo mysql -e "ALTER USER 'ocs'@'localhost' IDENTIFIED BY 'YOUR_DB_PASSWORD'; FLUSH PRIVILEGES;"
```

2. Прописать новый пароль в обоих файлах (список выше).
3. Включить mod_perl и конфигурацию сервера, перезапустить Apache и проверить логи:

```bash
sudo a2enmod perl
sudo a2enconf z-ocsinventory-server
sudo systemctl restart apache2
sudo tail -n 50 /var/log/apache2/error.log
```

Проверка: запусти инвентаризацию самого сервера и убедись, что он появился в веб-интерфейсе:

```bash
sudo ocsinventory-agent --debug --force
```

### Агент на Linux-клиентах

Для установки агента на Linux-машины (Debian/Ubuntu) используется скрипт [`scripts/install_ocs_agent.sh`](scripts/install_ocs_agent.sh): он ставит пакет `ocsinventory-agent`, прописывает адрес сервера в `/etc/ocsinventory/ocsinventory-agent.cfg` и запускает первую инвентаризацию.

```bash
sudo OCS_SERVER=http://<IP_сервера>/ocsinventory ./install_ocs_agent.sh
```

---

## Шаг 7. SNMP и MIB-файлы

Для сканирования сетевых устройств:

```bash
sudo apt install nmap libnet-snmp-perl snmp snmp-mibs-downloader -y
sudo download-mibs
```

MIB-файл производителя (в моём случае принтеры Kyocera) кладётся в каталог MIB:

```bash
sudo mv KYOCERA-Private-MIB /usr/share/snmp/mibs
```

Проверка доступности устройства по SNMP:

```bash
snmpwalk -v2c -c <community> <IP_устройства>
snmpget  -v2c -c <community> <IP_устройства> .1.3.6.1.2.1.1.1.0   # sysDescr
snmpget  -v2c -c <community> <IP_устройства> .1.3.6.1.2.1.1.2.0   # sysObjectID
```

Если устройство отвечает, но в OCS не появляется, проблема в агенте или в настройке SNMP-сканирования, а не в сети.

---

## Шаг 8. SNMP-агент в Docker

Docker:

```bash
sudo apt install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker $USER    # затем перелогиниться
```

Образ собирается из файлов в каталоге [`docker-snmp-agent/`](docker-snmp-agent/):

- `Dockerfile`: база `debian:12-slim`, зависимости (Perl-модули, `nmap`, `arp-scan`, `libnet-snmp-perl` и др.), сборка OCS Unix Agent 2.10.5 из исходников (архив с GitHub OCSInventory-NG/UnixAgent) и настройка через `postinst.pl --nowizard --snmp`;
- `entrypoint.sh`: бесконечный цикл, который запускает агент и ждёт `OCS_INTERVAL` секунд (по умолчанию 3600).

Отдельные `modules.conf` и `ocsinventory-agent.cfg` в образ не копируются: при сборке `postinst.pl` с флагом `--snmp` сам создаёт конфигурацию в каталоге `/etc/ocsinventory-agent/` внутри контейнера и подключает SNMP-модули.

Сборка и запуск:

```bash
cd ~/ocs-snmp-agent
docker build -t ocs-snmp-agent .

docker run -d --name ocs-snmp-agent --network host --restart unless-stopped \
  -e OCS_SERVER="http://localhost/ocsinventory" \
  -e OCS_TAG="SNMP-COLLECTOR" \
  ocs-snmp-agent
```

`--network host` нужен, чтобы контейнер видел подсети с устройствами и обращался к серверу OCS на том же хосте по `localhost`.

Переменные окружения контейнера: `OCS_SERVER` (адрес сервера), `OCS_TAG` (тег устройства в OCS, по умолчанию `SNMP-COLLECTOR`), `OCS_INTERVAL` (период запуска в секундах, по умолчанию `3600`).

Проверка вручную с отладкой:

```bash
docker exec -it ocs-snmp-agent ocsinventory-agent --server=http://localhost/ocsinventory --force --debug
docker logs -f ocs-snmp-agent
```

Признак работающего SNMP-сканирования: в логе идут строки `[snmpscan] Scanning device ...` по адресам устройств в сети.

Пересборка после правок `Dockerfile` или `entrypoint.sh`:

```bash
docker build -t ocs-snmp-agent .
docker stop ocs-snmp-agent && docker rm ocs-snmp-agent
# затем снова docker run (см. выше)
```

---

## Шаг 9. Мониторинг сервера: Zabbix Agent 2

```bash
wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-1+ubuntu24.04_all.deb
sudo dpkg -i zabbix-release_7.0-1+ubuntu24.04_all.deb
sudo apt update
sudo apt install zabbix-agent2 -y
sudo nano /etc/zabbix/zabbix_agent2.conf      # Server=, ServerActive=, Hostname=
sudo systemctl enable --now zabbix-agent2
sudo systemctl restart zabbix-agent2
sudo systemctl status zabbix-agent2
```

---

## Шаг 10. Траблшутинг

Первой диагностикой всегда служит лог Apache:

```bash
sudo tail -n 50 /var/log/apache2/error.log
```

**Установка из пакетов (PPA) не сработала, пришлось ставить из исходников.**
Сначала сервер ставился пакетами `ocsinventory-server` и `ocsinventory-reports` из PPA. Пришлось вручную доустанавливать Perl-модули (`XML::Entities`, `SOAP::Lite`, `DBD::mysql`, `Apache::DBI`), запускать `composer install`, а в веб-интерфейсе возникли проблемы с уровнем доступа пользователя `admin` (правки таблицы `operators` в БД и файла `html_header.php`). В итоге всё было удалено и поставлено чисто из исходников, что сработало:

```bash
sudo apt purge ocsinventory-server ocsinventory-reports -y
sudo apt autoremove -y
sudo rm -rf /etc/ocsinventory-server /usr/share/ocsinventory-reports /var/lib/ocsinventory-reports
sudo rm -f /etc/apache2/conf-available/{ocsinventory-reports,z-ocsinventory-server}.conf
sudo rm -f /etc/apache2/conf-enabled/{ocsinventory-reports,z-ocsinventory-server}.conf
sudo mysql -e "DROP DATABASE IF EXISTS ocsweb; DROP USER IF EXISTS 'ocs'@'localhost'; FLUSH PRIVILEGES;"
sudo systemctl restart apache2
```

**`Can't locate ....pm` в error.log.** Не хватает Perl-модуля: поставь соответствующий пакет `lib...-perl`. Так добавлялись `libdbd-mysql-perl`, `libapache-dbi-perl`, `libsoap-lite-perl`, `libmojolicious-perl`, `libplack-perl`.

**Ошибка доступа к БД / пустой веб-интерфейс.** Пароль пользователя `ocs` отличается в `dbconfig.inc.php` и `z-ocsinventory-server.conf`. Привести к одному значению и перезапустить Apache.

**Проблемы с сессиями в веб-интерфейсе.** Помогла очистка старых сессий PHP: `sudo rm -f /var/lib/php/sessions/sess_*` и перезапуск Apache.

**Устройство отвечает по `snmpget`, но не попадает в OCS.** Отладить агент: `docker exec -it ocs-snmp-agent ocsinventory-agent --server=http://localhost/ocsinventory --force --debug`, посмотреть, уходят ли в сервер запросы с блоком `SNMP`.

**Установка агента/пакетов зависает, репозитории недоступны.** Проверь доступность из сети сервера: `ping`, `curl -v https://<хост>`. В моей сети репозиторий OCS был недоступен, поэтому архивы качались напрямую с GitHub.

---

## Что можно улучшить

- Вынести пароли БД в отдельный файл с ограниченными правами и не хранить их в истории команд.
- После установки вернуть `root` MariaDB на unix-сокет или задать сильный пароль.
- Закрыть веб-интерфейс OCS доступом только из корпоративной подсети и повесить его на HTTPS.
- Заменить `memory_limit = -1` в PHP на конкретное ограничение и задать `date.timezone` в `php.ini` (сейчас параметр закомментирован).
- В `entrypoint.sh` агент запускается с `--ssl=0` (проверка сертификата отключена). При переходе на HTTPS включить проверку.
