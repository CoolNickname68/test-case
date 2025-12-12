#!/bin/bash

# Конфигурация
LOG_FILE="/var/log/monitoring.log"
MONITOR_URL="http://example.com"
PROCESS_NAME="test"
PID_FILE="/var/run/test-monitor.pid"
STATE_FILE="/var/run/test-monitor.state"

# Настройка umask для безопасности
umask 0027

# Функция безопасного логирования
log_message() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    
    echo "$message" 2>/dev/null >> "$LOG_FILE" || true
    
    # Всегда пишем в syslog
    logger -t "process-monitor" "$1"
}

# Функция безопасной записи в файл
safe_write() {
    local file="$1"
    local content="$2"
    

    local temp_file="${file}.$$.tmp"
    
    if echo "$content" 2>/dev/null > "$temp_file"; then
        if mv -f "$temp_file" "$file" 2>/dev/null; then
            return 0
        else
            rm -f "$temp_file" 2>/dev/null || true
            log_message "ОШИБКА: Не удалось переместить файл $temp_file в $file"
            return 1
        fi
    else
        log_message "ОШИБКА: Не удалось записать в $temp_file"
        return 1
    fi
}

# Функция безопасного чтения файла
safe_read() {
    local file="$1"
    
    if [ -r "$file" ] && [ -f "$file" ]; then
        cat "$file" 2>/dev/null | tr -d '\n\r' || echo ""
    else
        echo ""
    fi
}

# Проверка запущен ли процесс (ровно один экземпляр)
check_process() {
    local pid_count
    
    # Используем pidof для более надежного определения
    pid_count=$(pidof "$PROCESS_NAME" 2>/dev/null | wc -w)
    
    if [ "$pid_count" -eq 1 ]; then
        return 0
    elif [ "$pid_count" -eq 0 ]; then
        return 1
    else
        log_message "ПРЕДУПРЕЖДЕНИЕ: Найдено $pid_count процессов с именем $PROCESS_NAME"
        return 0
    fi
}

# Получение PID процесса (первого найденного)
get_process_pid() {
    # Используем pidof и берем первый PID
    pidof "$PROCESS_NAME" 2>/dev/null | awk '{print $1}' | tr -d '\n\r'
}

# Простая и надежная отправка HTTP запроса
send_http_request() {
    local response_code
    local max_retries=3
    local retry_delay=2
    local attempt=1
    local curl_output
    local http_code
    
    if [[ ! "$MONITOR_URL" =~ ^https?:// ]]; then
        log_message "ОШИБКА КОНФИГУРАЦИИ: URL должен содержать протокол (http:// или https://)"
        return 1
    fi
    
    while [ $attempt -le $max_retries ]; do
        response_code=$(curl -s \
            -o /dev/null \
            -w "%{http_code}" \
            -H "Content-Type: application/json" \
            -H "User-Agent: ProcessMonitor/1.0" \
            -m 10 \
            --connect-timeout 5 \
            "$MONITOR_URL" 2>&1)
        
        # Проверяем, что response_code содержит только цифры
        if [[ "$response_code" =~ ^[0-9]+$ ]]; then
            http_code="$response_code"
        else
            # Если curl вернул не только код, извлекаем код
            http_code=$(echo "$response_code" | grep -o '[0-9][0-9][0-9]' | head -1)
            if [ -z "$http_code" ]; then
                http_code="000"
            fi
        fi
        
        case "$http_code" in
            200|201)
                log_message "УСПЕХ: HTTP запрос выполнен. Код: $http_code"
                return 0
                ;;
            000)
                # Код 000 означает, что curl не смог установить соединение
                log_message "ОШИБКА СЕТИ ($attempt/$max_retries): Не удалось установить соединение"
                
                if [ $attempt -lt $max_retries ]; then
                    sleep $retry_delay
                fi
                ;;
            4[0-9][0-9])
                # Ошибки клиента 4xx
                log_message "ОШИБКА КЛИЕНТА: HTTP код $http_code"
                return 1
                ;;
            5[0-9][0-9]|429)
                # Ошибки сервера 5xx и rate limiting
                log_message "ОШИБКА СЕРВЕРА ($attempt/$max_retries): HTTP код $http_code"
                if [ $attempt -lt $max_retries ]; then
                    sleep $retry_delay
                fi
                ;;
            *)
                # Другие коды
                log_message "НЕИЗВЕСТНЫЙ КОД ($attempt/$max_retries): HTTP код $http_code"
                if [ $attempt -lt $max_retries ]; then
                    sleep $retry_delay
                fi
                ;;
        esac
        attempt=$((attempt + 1))
    done
    
    log_message "ОШИБКА: Не удалось выполнить HTTP запрос после $max_retries попыток"
    return 1
}

# Основная логика
main() {
    local current_pid
    local previous_pid
    
    # Проверяем запущен ли процесс
    if check_process; then
        current_pid=$(get_process_pid)
        
        if [ -z "$current_pid" ]; then
            log_message "ОШИБКА: Не удалось определить PID процесса $PROCESS_NAME"
            exit 1
        fi
        
        # Читаем предыдущий PID из state файла
        previous_pid=$(safe_read "$STATE_FILE")
        
        # Проверяем был ли перезапуск
        if [ -n "$previous_pid" ] && [ "$current_pid" != "$previous_pid" ]; then
            log_message "ПЕРЕЗАПУСК: Процесс $PROCESS_NAME перезапущен. Старый PID: $previous_pid, Новый PID: $current_pid"
        else
            log_message "ИНФО: Процесс $PROCESS_NAME работает. PID: $current_pid"
        fi
        
        # Сохраняем текущий PID
        if ! safe_write "$STATE_FILE" "$current_pid"; then
            log_message "ОШИБКА: Не удалось сохранить состояние в $STATE_FILE"
            exit 1
        fi
        
        # Отправляем HTTP запрос
        if ! send_http_request; then
            exit 1
        fi
        
        log_message "УСПЕХ: Процесс $PROCESS_NAME (PID: $current_pid) мониторится успешно"
    else
        # Процесс не запущен - очищаем state файл
        if [ -f "$STATE_FILE" ]; then
            rm -f "$STATE_FILE" || log_message "ПРЕДУПРЕЖДЕНИЕ: Не удалось удалить $STATE_FILE"
        fi
        log_message "ИНФО: Процесс $PROCESS_NAME не запущен"
    fi
}

# Обработка сигналов
trap 'log_message "СКРИПТ: Получен сигнал завершения"; exit 0' INT TERM

# Запуск основной функции
main "$@"