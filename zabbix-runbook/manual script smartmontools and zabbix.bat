@echo off
:: --- 1. Удаляем старый Zabbix Agent (v1), если он существует ---
:: Делаем это тихо, чтобы скрипт не ругался, если старого агента изначально не было

:: Останавливаем службу перед удалением
sc stop "Zabbix Agent" > NUL 2>&1
timeout /t 3 /nobreak > NUL

:: Пытаемся удалить через WMIC по имени продукта (штатный способ деинсталляции MSI)
wmic product where "name like 'Zabbix Agent%%' and not name like 'Zabbix Agent 2%%'" call uninstall /nointeractive > NUL 2>&1

:: На случай, если WMIC не нашёл продукт (например, установлен не через MSI) -
:: подчищаем службу вручную, чтобы она не мешала и не путалась с Agent 2
sc query "Zabbix Agent" > NUL 2>&1
IF %ERRORLEVEL% EQU 0 (
    sc stop "Zabbix Agent" > NUL 2>&1
    sc delete "Zabbix Agent" > NUL 2>&1
)

:: --- 1.5. Чистим "осиротевшие" остатки Zabbix Agent 2 ---
:: Бывает, что MSI Agent 2 когда-то ставился и был снесён не через штатный uninstall
:: (например, вручную удалили файлы/папку). Тогда в реестре остаются висячие
:: записи службы и/или источника событий, из-за которых новая установка падает
:: с ошибкой "registry key already exists". Чистим их заранее, чтобы установка
:: прошла с первого раза без ручного вмешательства.

:: Останавливаем и удаляем саму службу, если она есть, но файла экзешника уже нет
sc query "Zabbix Agent 2" > NUL 2>&1
IF %ERRORLEVEL% EQU 0 (
    IF NOT EXIST "C:\Program Files\Zabbix Agent 2\zabbix_agent2.exe" (
        sc stop "Zabbix Agent 2" > NUL 2>&1
        sc delete "Zabbix Agent 2" > NUL 2>&1
    )
)

:: Удаляем зависший ключ источника событий (главная причина ошибки "registry key already exists")
:: Проверяем сначала, есть ли он вообще, чтобы не плодить ошибки в консоли
reg query "HKLM\SYSTEM\CurrentControlSet\Services\EventLog\Application\Zabbix Agent 2" > NUL 2>&1
IF %ERRORLEVEL% EQU 0 (
    reg delete "HKLM\SYSTEM\CurrentControlSet\Services\EventLog\Application\Zabbix Agent 2" /f > NUL 2>&1
)

:: --- 2. Установка Zabbix Agent 2 ---
IF EXIST "C:\Program Files\Zabbix Agent 2\zabbix_agent2.exe" GOTO CHECK_SMART

:: Тихая установка Zabbix Agent 2 с ожиданием завершения (start /wait)
:: Также пишем лог установки прямо на диск C:\zabbix_install_log.txt
start /wait msiexec /i "\\10.38.38.11\Share\AD_GPO\zabbix_agent2\zabbix_agent2.msi" SERVER=10.38.1.177 SERVERACTIVE=10.38.1.177 /qn /l*v "C:\zabbix_install_log.txt"

:: Даем время на установку и регистрацию службы
timeout /t 10 /nobreak > NUL

:CHECK_SMART
:: --- 3. Установка smartmontools ---
IF EXIST "C:\Program Files\smartmontools\bin\smartctl.exe" GOTO CONFIGURE_ZABBIX

:: Запускаем тихую установку из сетевой шары (путь взял из твоего старого скрипта)
"\\10.38.38.11\Share\AD_GPO\smartmontools\smartmontools-7.5.exe" /S

:: Даем время на распаковку файлов
timeout /t 10 /nobreak > NUL

:CONFIGURE_ZABBIX
:: --- 4. Настройка связки Zabbix Agent 2 и smartmontools ---
:: Создаем папку для плагинов Zabbix Agent 2, если её вдруг нет
IF NOT EXIST "C:\Program Files\Zabbix Agent 2\zabbix_agent2.d\plugins.d" mkdir "C:\Program Files\Zabbix Agent 2\zabbix_agent2.d\plugins.d"

:: Прописываем путь к smartctl.exe в конфигурационный файл
echo Plugins.Smart.Path=C:\PROGRA~1\smartmontools\bin\smartctl.exe > "C:\Program Files\Zabbix Agent 2\zabbix_agent2.d\plugins.d\smart.conf"

:: Перезапускаем новую службу Zabbix Agent 2, чтобы она подхватила плагин SMART
net stop "Zabbix Agent 2"
net start "Zabbix Agent 2"

:END
exit