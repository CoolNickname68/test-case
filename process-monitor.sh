#!/bin/bash

# Конфигурация
LOG_FILE="/var/log/monitoring.log"
MONITOR_URL="https://test.com/monitoring/test/api"
PROCESS_NAME="test"
PID_FILE="/var/run/test-monitor.pid"
STATE_FILE="/var/run/test-monitor.state"

# Функция логирования
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    logger -t "process-monitor" "$1"
}

# Проверка запущен ли процесс
check_process() {
    pgrep -x "$PROCESS_NAME" > /dev/null
    return $?
}

# Получение PID процесса
get_process_pid() {
    pgrep -x "$PROCESS_NAME"
}

# Отправка HTTP запроса
send_http_request() {
    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Content-Type: application/json" \
        -H "User-Agent: ProcessMonitor/1.0" \
        -m 10 \
        "$MONITOR_URL")
    
    if [ "$response_code" = "200" ] || [ "$response_code" = "201" ]; then
        return 0
    else
        log_message "ОШИБКА: Сервер мониторинга недоступен. HTTP код: $response_code"
        return 1
    fi
}

# Основная логика
main() {
    # Проверяем запущен ли процесс
    if check_process; then
        current_pid=$(get_process_pid)
        
        # Читаем предыдущий PID из state файла
        if [ -f "$STATE_FILE" ]; then
            previous_pid=$(cat "$STATE_FILE")
        else
            previous_pid=""
        fi
        
        # Проверяем был ли перезапуск
        if [ -n "$previous_pid" ] && [ "$current_pid" != "$previous_pid" ]; then
            log_message "ПЕРЕЗАПУСК: Процесс $PROCESS_NAME перезапущен. Старый PID: $previous_pid, Новый PID: $current_pid"
        fi
        
        # Сохраняем текущий PID
        echo "$current_pid" > "$STATE_FILE"
        
        # Отправляем HTTP запрос
        if ! send_http_request; then
            exit 1
        fi
    else
        # Процесс не запущен - ничего не делаем
        rm -f "$STATE_FILE"
    fi
}

# Запуск
main "$@"