#!/bin/bash
# Быстрая проверка записи в лог
# sudo ./quick_test.sh

echo "=== БЫСТРАЯ ПРОВЕРКА МОНИТОРИНГА ==="

# Создаем лог если нет
sudo touch /var/log/monitoring.log 2>/dev/null
sudo chmod 644 /var/log/monitoring.log 2>/dev/null

# Убиваем старые процессы
sudo pkill -x test 2>/dev/null

echo "1. Запускаем первый процесс test..."
sleep 1000 &
FIRST_PID=$!
sudo sh -c "echo test > /proc/$FIRST_PID/comm" 2>/dev/null || echo "Процесс создан: $FIRST_PID"

echo "2. Первый запуск мониторинга..."
sudo /usr/local/bin/process-monitor.sh 2>/dev/null

echo "3. Перезапускаем процесс..."
sudo kill $FIRST_PID 2>/dev/null
sleep 1000 &
SECOND_PID=$!
sudo sh -c "echo test > /proc/$SECOND_PID/comm" 2>/dev/null || echo "Новый процесс: $SECOND_PID"

echo "4. Второй запуск мониторинга (должна быть запись)..."
sudo /usr/local/bin/process-monitor.sh 2>/dev/null

echo -e "\n=== РЕЗУЛЬТАТ ==="
if sudo tail -1 /var/log/monitoring.log 2>/dev/null | grep -q "ПЕРЕЗАПУСК"; then
    echo "✅ УСПЕХ: Запись в логе найдена!"
    sudo tail -5 /var/log/monitoring.log
else
    echo "❌ ОШИБКА: Запись в логе НЕ найдена"
    echo "Содержимое лога:"
    sudo cat /var/log/monitoring.log 2>/dev/null || echo "Лог-файл пуст или отсутствует"
fi

# Очистка
sudo kill $SECOND_PID 2>/dev/null
