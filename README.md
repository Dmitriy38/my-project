# my-project

Репозиторий с инфраструктурными проектами: развёртывание сервисов, мониторинг и автоматизация. Каждый проект оформлен как runbook — по нему можно повторить установку с нуля, там же разобраны реальные проблемы, с которыми пришлось столкнуться, и как они были решены.

## Проекты

### [Vaultwarden: корпоративный менеджер паролей](vaultwarden-runbook/)
Self-hosted Bitwarden-совместимый сервер в закрытой сети: Docker, Nginx Proxy Manager, локальный SSL-сертификат с SAN, внутренний DNS, изоляция контейнеров через UFW и `DOCKER-USER`. Отдельно разобрана проблема с доставкой почты на Hyper-V (offloading контрольных сумм) и конфликт UFW с сетью Docker после `ufw reload`.

**Стек:** Docker, Docker Compose, Nginx Proxy Manager, MariaDB, UFW, OpenSSL, Active Directory DNS

### [Zabbix: мониторинг инфраструктуры и SMART-дисков](zabbix-monitoring/)
Мониторинг Windows-рабочих станций на 18 подсетях с упором на раннее обнаружение отказов дисков. Массовое развёртывание агента через GPO, автообнаружение хостов по всем подсетям, SMART-мониторинг (SSD/NVMe/HDD) через Dependent items и JavaScript-предобработку без скриптов на хостах, автоматизация через Zabbix API на Python.

**Стек:** Zabbix Server, Zabbix Agent 2, smartmontools, Python 3 + `requests`, GPO, cron

### [OCS Inventory: инвентаризация оборудования + SNMP](ocs-inventory-runbook/)
Сервер инвентаризации на связке Apache + MariaDB + PHP + Perl, установленный из исходников после неудачной попытки через PPA-пакеты. Сбор данных с сетевых устройств без агента (принтеры и т.п.) по SNMP через собственный Docker-образ агента. Мониторинг самого сервера через Zabbix Agent 2.

**Стек:** Ubuntu Server, Apache, MariaDB, PHP, Perl, Docker, SNMP, Zabbix Agent 2

### [BitATS: мониторинг звонков колл-центра](bitats-call-monitoring/)
Дашборд в реальном времени по звонкам, очередям и операторам колл-центра. Штатная аналитика BitATS дополнена самописным AMI-поллером на Python (статус очередей и операторов через Asterisk Manager Interface), Zabbix следит за регистрацией SIP-транков и активными звонками, всё выведено на дашборд Grafana с SQL и Zabbix как источниками данных.

**Стек:** Asterisk (BitATS/BitPBX), MySQL/MariaDB, Python 3, Zabbix 7.0, Grafana, systemd

## Об авторе

Дмитрий Попов, системный администратор, Иркутск. Ищу позицию DevOps-инженера.
