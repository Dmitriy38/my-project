#!/bin/bash

#variables(переменные)

PROCESS_NAME="test"
API_URL="https://test.com/monitoring/test/api"
LOG_FILE="/var/log/monitoring.log"
PID_FILE="/tmp/test_process.pid"

#Функция логирования с датой

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

#Получения PID процесса. А Флаг -х будет искать точное совпадение имени.

CURRENT_PID=$(ps aux | grep -E "[t]est " | grep -v grep | head -1 | awk '{print $2}')

#Если процесс запущен (PID не пустой)
if [ -n "$CURRENT_PID" ]; then

    #Требование под номером 4: Проверка на перезапуск 
    #Если файл с прошлым PID существует, читаем его
    if [ -f "$PID_FILE" ]; then
        OLD_PID=$(cat "$PID_FILE")

        #Если старый PID был записан и он не равен текущему - процесс перезапустился
        if [ -n "$OLD_PID" ] && [ "$OLD_PID" != "$CURRENT_PID" ]; then
            log_message "Process '$PROCESS_NAME' was restarted. Old PID: $OLD_PID, New PID: $CURRENT_PID"
        fi
    fi

    #Обновляем PID файл текущим значением
    echo "$CURRENT_PID" > "$PID_FILE"

    #Требование задания 3 и 5: Стучимся на API и проверяем доступность 
    #-s:silent mode, -f:fail silently (возвращает ошибку, если HTTP code >= 400), -o /dev/null:не выводить тело ответа
    if ! curl -sf -o /dev/null "$API_URL"; then
        log_message "Monitoring server unavailable: $API_URL"
    fi

else
    #Процесс не запущен.
    #Согласно требованию:"если процесс не запущен, то ничего не делать".
    #Мы просто выходим, не обновляя PID файл (чтобы при следующем запуске процесса мы увидели смену PID)
    exit 0
fi

