# 1. Копируем скрипт
sudo cp process-monitor.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/process-monitor.sh

# 2. Создаем systemd файлы
sudo cp process-monitor.service /etc/systemd/system/
sudo cp process-monitor.timer /etc/systemd/system/

# 3. Включаем и запускаем
sudo systemctl daemon-reload
sudo systemctl enable process-monitor.timer
sudo systemctl start process-monitor.timer
sudo chmod 666 /var/log/monitoring.log
sudo touch /var/run/test-monitor.state
sudo chmod 644 /var/run/test-monitor.state
# 4. Проверяем статус
#sudo systemctl status process-monitor.timer
#journalctl -u process-monitor.service -f