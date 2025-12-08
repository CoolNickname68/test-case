#!/bin/bash
# test_monitor_working.sh - Рабочий тест мониторинга
# Использует временное изменение PROCESS_NAME на 'sleep' для проверки

echo "=== ТЕСТ МОНИТОРИНГА С 'sleep' ==="

# 1. Сохраняем оригинальный скрипт
sudo cp /usr/local/bin/process-monitor.sh /usr/local/bin/process-monitor.sh.backup

# 2. Временно меняем PROCESS_NAME на 'sleep'
sudo sed -i 's/PROCESS_NAME="test"/PROCESS_NAME="sleep"/' /usr/local/bin/process-monitor.sh

# 3. Очищаем файлы
sudo rm -f /var/log/monitoring.log /var/run/test-monitor.state

# 4. Запускаем sleep процесс
sleep 3000 &
PID1=$!
echo "Первый sleep PID: $PID1"

# 5. Первый запуск мониторинга
echo "Первый запуск мониторинга..."
sudo /usr/local/bin/process-monitor.sh
echo "STATE_FILE: $(cat /var/run/test-monitor.state 2>/dev/null || echo 'нет')"

# 6. Перезапускаем sleep
kill $PID1 2>/dev/null
sleep 3000 &
PID2=$!
echo "Второй sleep PID: $PID2"

# 7. Второй запуск мониторинга
echo "Второй запуск мониторинга (должна быть запись в лог)..."
sudo /usr/local/bin/process-monitor.sh

# 8. Проверяем лог
echo -e "\n=== РЕЗУЛЬТАТ ==="
if sudo grep -q "ПЕРЕЗАПУСК" /var/log/monitoring.log 2>/dev/null; then
    echo "✅ УСПЕХ: Мониторинг работает!"
    sudo tail -5 /var/log/monitoring.log
else
    echo "❌ ПРОБЛЕМА: Запись не найдена"
    sudo cat /var/log/monitoring.log 2>/dev/null || echo "Лог пуст"
fi

# 9. Восстанавливаем оригинальный скрипт
sudo cp /usr/local/bin/process-monitor.sh.backup /usr/local/bin/process-monitor.sh

# 10. Очистка
pkill -f "sleep 3000" 2>/dev/null