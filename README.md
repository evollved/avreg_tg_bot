Сохраните tg.sh
Замените значения в файле на свои (токен tg, ID чата, номер камеры и логин)
Файл нужно скоприровать в /etc/avreg/scripts
Заменить ему права и пользователя на 0755 root:root
Отредактировать avreg.conf в соответствии с инструкцией по обработке внешних событий (http://avreg.net/manual_applications_monitoring-with-event-collector.html):

в терминале:

cp tg.sh /etc/avreg/scripts/tg.sh
sudo chown root:root /etc/avreg/scripts/tg.sh
sudo chmod 0755 /etc/avreg/scripts/tg.sh

cd /etc/avreg/scripts
sudo cp /usr/share/doc/avregd/examples/event-collector.gz /etc/avreg/scripts
sudo gunzip event-collector.gz

sudo chown root:root /etc/avreg/scripts/event-collector
sudo chmod 0755 /etc/avreg/scripts/event-collector

Отредактируйте event-collector любым удобным редактром.

После строки 369 (   log debug "cam[$cam_nr]: #$session_nr motion session $status at $dt_event (diff: $diff/$threshold;.......), добавляем:
exec "/etc/avreg/scripts/tg.sh"

Сохраняем изменения и заходим в настройки камеры, номер которой указывали в tg.sh
(По умолчанию http://ip сервера/avreg) Вводиим логин и пароль (по умолчанию install без пароля - не забудьте поменять) Настройки и управление -> настройки -> видеокамеры -> ваша камера, вкладка события. Тут нужно в events2pipe поставить галку "Движение" и нажать сохранить.
Теперь возвращаемся на главную (Назад в Админ) - управление и перезапускаем сервер (Restart).

Если всё сделано верно - вы получите первые пару уведомлений.
