# FortressBackup - Secure Automated Backups

### Overview
FortressBackup is a simple yet secure backup solution that keeps your backup server mostly closed to the outside world, only opening ports when necessary for backup transfers.

### Features
- One-command installation
- Automatic backup scheduling via cron
- Multiple backup jobs with different schedules
- SSH key authentication (no passwords)
- Temporary port opening (5 minutes)
- Checksum verification for data integrity
- Web management interface (optional)
- Complete uninstaller

### Requirements
- Linux (Ubuntu 20.04+ recommended)
- Two servers (or one for testing)
- Root access

### Quick Start

#### 1. Install Backup Server (storage server)
```bash
git clone https://github.com/yourusername/fortressbackup.git
cd fortressbackup
make server
```
You will be prompted for:
- Server IP address
- SSH port (default: 22)
- Backup transfer port (default: 2222)

#### 2. Install Backup Client (source server)
```bash
git clone https://github.com/yourusername/fortressbackup.git
cd fortressbackup
make client
```
You will be prompted for:
- Backup server IP address
- SSH port (default: 22)
- Backup transfer port (default: 2222)
- What to backup (e.g., /var/www /etc)
- Backup time (e.g., 02:00)

During installation, an SSH key will be displayed. Copy it and add to the backup server:
```bash
echo 'YOUR_SSH_KEY' | sudo tee -a /home/backupuser/.ssh/authorized_keys
```

#### 3. Verify Installation
```bash
# Run backup manually
sudo /usr/local/bin/fortress-backup

# Check logs
tail -f /var/log/fortressbackup.log
```

### Commands

#### Installation
```bash
make server      # Install backup server
make client      # Install backup client
make web         # Install web interface (optional)
```

#### Management
```bash
make backup-list      # List all backup jobs
make backup-add       # Add new backup job (interactive)
make uninstall        # Completely remove FortressBackup
```

#### Manual Backup
```bash
# Run all enabled backups
sudo /usr/local/bin/fortress-backup

# Run specific backup by ID
sudo /usr/local/bin/fortress-backup --backup-id 1
```

### Web Interface (Optional)

Install with:
```bash
make web
```

Access at: `http://your-server-ip:5000`
Default password: set during installation

Web interface features:
- View backup jobs
- Add/remove backups
- Enable/disable backups
- View backup logs
- View access logs
- View free space on backup server
- Change password

### Configuration Files

#### Client: `/etc/fortressbackup-client.conf`
```ini
SERVER_IP=192.168.1.100
SSH_PORT=22
BACKUP_PORT=2222

BACKUP_1_ENABLED=true
BACKUP_1_SOURCES=/var/www
BACKUP_1_TIME=02:00
BACKUP_1_SCHEDULE=daily

BACKUP_2_ENABLED=true
BACKUP_2_SOURCES=/etc
BACKUP_2_TIME=03:00
BACKUP_2_SCHEDULE=weekly
```

#### Server: `/etc/fortressbackup-server.conf`
```ini
SERVER_IP=192.168.1.100
SSH_PORT=22
BACKUP_PORT=2222
```

### Directory Structure

#### Backup Server
```
/backups/
├── incoming/    # Temporary storage during transfer
└── archive/     # Permanent backup storage
```

#### Client
```
/var/log/fortressbackup.log    # Backup logs
/root/.ssh/id_ed25519_fortress # SSH private key
/etc/fortressbackup-client.conf # Client configuration
```

### Security Model
1. Backup server keeps all ports closed by default
2. Client sends encrypted SSH signal to open backup port
3. Port opens for exactly 5 minutes
4. Backup transfers via SCP over SSH
5. SHA256 checksum verification
6. Port automatically closes
7. Backup moved to archive after verification

### Logs
```bash
# View backup logs
tail -f /var/log/fortressbackup.log

# View web interface logs
sudo journalctl -u fortress-backup-web -f

# View SSH access logs
tail -f /var/log/auth.log | grep sshd
```

### Troubleshooting

#### SSH connection fails
```bash
# Check SSH service
sudo systemctl status ssh

# Verify key is added
cat /home/backupuser/.ssh/authorized_keys

# Check permissions
chmod 700 /home/backupuser/.ssh
chmod 600 /home/backupuser/.ssh/authorized_keys
```

#### Backup not sending
```bash
# Check logs
tail -f /var/log/fortressbackup.log

# Manual test
ssh -i /root/.ssh/id_ed25519_fortress backupuser@SERVER_IP
```

#### Cron not working
```bash
# Check crontab
sudo crontab -l

# Add manually
sudo crontab -e
# Add: 0 2 * * * /usr/local/bin/fortress-backup >> /var/log/fortressbackup.log 2>&1
```

### Uninstall
```bash
make uninstall
```
Removes:
- All backups
- backupuser account
- Scripts and configuration
- Cron jobs
- Logs
- Web interface and service
- SSH keys
- Open ports

### License
MIT

---


### Обзор
FortressBackup — это простое и безопасное решение для автоматического резервного копирования. Сервер хранения бэкапов большую часть времени закрыт, порты открываются только на время передачи данных.

### Возможности
- Установка одной командой
- Автоматическое расписание через cron
- Несколько бэкапов с разным расписанием
- Аутентификация по SSH ключам (без паролей)
- Временное открытие порта (5 минут)
- Проверка целостности через контрольные суммы
- Веб-интерфейс управления (опционально)
- Полное удаление системы

### Требования
- Linux (рекомендуется Ubuntu 20.04+)
- Два сервера (или один для тестирования)
- Root доступ

### Быстрый старт

#### 1. Установка сервера бэкапов (хранилище)
```bash
git clone https://github.com/yourusername/fortressbackup.git
cd fortressbackup
make server
```
Будут запрошены:
- IP адрес сервера
- SSH порт (по умолчанию: 22)
- Порт для передачи бэкапов (по умолчанию: 2222)

#### 2. Установка клиента (сервер с данными)
```bash
git clone https://github.com/yourusername/fortressbackup.git
cd fortressbackup
make client
```
Будут запрошены:
- IP адрес сервера бэкапов
- SSH порт (по умолчанию: 22)
- Порт для передачи бэкапов (по умолчанию: 2222)
- Что бэкапить (например: /var/www /etc)
- Время бэкапа (например: 02:00)

Во время установки будет показан SSH ключ. Скопируйте его и добавьте на сервер бэкапов:
```bash
echo 'ВАШ_SSH_КЛЮЧ' | sudo tee -a /home/backupuser/.ssh/authorized_keys
```

#### 3. Проверка установки
```bash
# Ручной запуск бэкапа
sudo /usr/local/bin/fortress-backup

# Просмотр логов
tail -f /var/log/fortressbackup.log
```

### Команды

#### Установка
```bash
make server      # Установка сервера бэкапов
make client      # Установка клиента
make web         # Установка веб-интерфейса (опционально)
```

#### Управление
```bash
make backup-list      # Список всех бэкапов
make backup-add       # Добавить новый бэкап (интерактивно)
make uninstall        # Полное удаление FortressBackup
```

#### Ручной запуск
```bash
# Запуск всех включенных бэкапов
sudo /usr/local/bin/fortress-backup

# Запуск конкретного бэкапа по ID
sudo /usr/local/bin/fortress-backup --backup-id 1
```

### Веб-интерфейс (Опционально)

Установка:
```bash
make web
```

Доступ: `http://ip-сервера:5000`
Пароль: устанавливается при установке

Возможности веб-интерфейса:
- Просмотр бэкапов
- Добавление/удаление бэкапов
- Включение/отключение бэкапов
- Просмотр логов бэкапов
- Просмотр логов доступа
- Просмотр свободного места на сервере бэкапов
- Смена пароля

### Файлы конфигурации

#### Клиент: `/etc/fortressbackup-client.conf`
```ini
SERVER_IP=192.168.1.100
SSH_PORT=22
BACKUP_PORT=2222

BACKUP_1_ENABLED=true
BACKUP_1_SOURCES=/var/www
BACKUP_1_TIME=02:00
BACKUP_1_SCHEDULE=daily

BACKUP_2_ENABLED=true
BACKUP_2_SOURCES=/etc
BACKUP_2_TIME=03:00
BACKUP_2_SCHEDULE=weekly
```

#### Сервер: `/etc/fortressbackup-server.conf`
```ini
SERVER_IP=192.168.1.100
SSH_PORT=22
BACKUP_PORT=2222
```

### Структура директорий

#### Сервер бэкапов
```
/backups/
├── incoming/    # Временное хранилище при передаче
└── archive/     # Постоянное хранилище бэкапов
```

#### Клиент
```
/var/log/fortressbackup.log        # Логи бэкапов
/root/.ssh/id_ed25519_fortress     # SSH приватный ключ
/etc/fortressbackup-client.conf    # Конфигурация клиента
```

### Модель безопасности
1. Сервер бэкапов по умолчанию закрыт
2. Клиент отправляет зашифрованный SSH сигнал для открытия порта
3. Порт открывается ровно на 5 минут
4. Бэкап передается через SCP поверх SSH
5. Проверка контрольной суммы SHA256
6. Порт автоматически закрывается
7. Бэкап перемещается в архив после проверки

### Логи
```bash
# Просмотр логов бэкапов
tail -f /var/log/fortressbackup.log

# Просмотр логов веб-интерфейса
sudo journalctl -u fortress-backup-web -f

# Просмотр логов SSH доступа
tail -f /var/log/auth.log | grep sshd
```

### Устранение проблем

#### Ошибка SSH подключения
```bash
# Проверка SSH сервиса
sudo systemctl status ssh

# Проверка добавленного ключа
cat /home/backupuser/.ssh/authorized_keys

# Проверка прав
chmod 700 /home/backupuser/.ssh
chmod 600 /home/backupuser/.ssh/authorized_keys
```

#### Бэкап не отправляется
```bash
# Проверка логов
tail -f /var/log/fortressbackup.log

# Ручная проверка подключения
ssh -i /root/.ssh/id_ed25519_fortress backupuser@IP_СЕРВЕРА
```

#### Cron не работает
```bash
# Проверка crontab
sudo crontab -l

# Добавление вручную
sudo crontab -e
# Добавить: 0 2 * * * /usr/local/bin/fortress-backup >> /var/log/fortressbackup.log 2>&1
```

### Удаление
```bash
make uninstall
```
Будет удалено:
- Все бэкапы
- Пользователь backupuser
- Скрипты и конфигурация
- Cron задачи
- Логи
- Веб-интерфейс и сервис
- SSH ключи
- Открытые порты

### Лицензия
MIT
