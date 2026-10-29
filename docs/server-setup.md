# Конфигурация виртуальной машины devops-vm

Документ достаточен, чтобы за 10 минут восстановить конфигурацию после отката на снимок `01-clean-install`. Пароли и закрытые ключи здесь не приводятся.

## 1. Параметры машины

- Имя: `devops-vm`
- Гостевая система: Ubuntu Server 24.04.5 LTS, не minimized, разметка Use an entire disk
- Память: 2048 МБ
- Процессоры: 2
- Диск: 25 ГБ, динамический VDI
- Прошивка: EFI
- Контроллер SATA: IntelAhci, кэш ввода-вывода хоста включён
- Пользователь установки: `student` (группа `sudo`)
- Имя узла после установки: `devops-vm`

Команды VirtualBox, если машину нужно создать заново:

```
VBoxManage createvm --name devops-vm --ostype Ubuntu24_LTS_64 --register
VBoxManage modifyvm devops-vm --memory 2048 --cpus 2 --nic1 nat --nic2 hostonly --hostonlyadapter2 "VirtualBox Host-Only Ethernet Adapter" --firmware efi
VBoxManage createmedium disk --filename devops-vm.vdi --size 25600
```

## 2. Сетевые интерфейсы

- Адаптер 1, NAT, в гостевой системе `enp0s3`: `10.0.2.15/24`. Нужен для выхода в интернет и для SSH с хоста через проброс портов.
- Адаптер 2, Host-only (`VirtualBox Host-Only Ethernet Adapter`), в гостевой системе `enp0s8`: `192.168.56.101/24`. Адрес хоста в этом сегменте: `192.168.56.1`.
- Проверка: `ip -brief address`

## 3. Правило проброса портов

Имя правила: `ssh`. Протокол TCP. Адрес хоста: `127.0.0.1`. Порт хоста: `2222`. Адрес гостя не задаётся.

- До усиления SSH порт гостя был `22`.
- После усиления порт гостя: `2222`.

```
VBoxManage controlvm devops-vm natpf1 delete ssh
VBoxManage controlvm devops-vm natpf1 "ssh,tcp,127.0.0.1,2222,,2222"
```

На хосте в `C:\Windows\System32\drivers\etc\hosts`:

```
192.168.56.101 devops.local
```

После правки: `ipconfig /flushdns`.

## 4. Учётные записи

- `student` — учётная запись установки, группа `sudo`. Вход по SSH после усиления закрыт директивой `AllowUsers devops`.
- `devops` — рабочая учётная запись, группы `devops`, `sudo`, `users`. Вход по ключу Ed25519.

Создание после отката на `01-clean-install` (выполнять от `student`):

```
sudo adduser devops
sudo usermod -aG sudo devops
```

На хосте отдельная пара, не ключ GitHub:

```
ssh-keygen -t ed25519 -C "devops-vm-key" -f %USERPROFILE%\.ssh\devops_vm
```

Открытый ключ — в `/home/devops/.ssh/authorized_keys`. Права: каталог `700`, файл `600`.

Фрагмент `%USERPROFILE%\.ssh\config`:

```
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

Проверка: `ssh devops` не запрашивает пароль.

## 5. Служба SSH

Файл `/etc/ssh/sshd_config` не изменяется. Копия: `/etc/ssh/sshd_config.backup`.

В `/etc/ssh/sshd_config.d/50-cloud-init.conf` строка `PasswordAuthentication yes` закомментирована. Иначе она срабатывает раньше файла `99-hardening.conf`, потому что OpenSSH берёт первое значение директивы.

Файл `/etc/ssh/sshd_config.d/99-hardening.conf`:

```
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

Применение, не закрывая уже открытую сессию:

```
sudo sshd -t && echo "Конфигурация корректна"
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd
```

Ожидается `0.0.0.0:2222`. Источник истины — `sudo sshd -T`, не текст файлов.

## 6. Правила межсетевого экрана

Политика по умолчанию: входящие `deny`, исходящие `allow`. Разрешение порта 2222 создаётся до `ufw enable`. Имя `ssh` не используется: в `/etc/services` оно означает порт 22.

```
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw delete allow 2222/tcp
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw logging medium
```

Итог `sudo ufw status verbose`: статус active, logging medium, Default: deny (incoming), allow (outgoing), правило `2222/tcp LIMIT`.

## 7. Снимки состояния

Снимки не удалять.

- `01-clean-install` — 2026-10-28 08:35 UTC. Система после установки и обновления пакетов, до пользователя `devops`.
- `02-keys-configured` — 2026-10-28 08:39 UTC. Вход `devops` по ключу, парольная аутентификация SSH ещё включена.
- `03-ssh-hardened` — 2026-10-29 11:32 UTC. SSH на порту 2222, только ключ, вход root запрещён. Снимок сделан до включения UFW.

Порядок восстановления с `01-clean-install`: разделы 4, 5, 6, затем запись `devops.local` из раздела 3 и полное имя:

```
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
hostname -f
```

Ожидается `devops-vm.devops.local`.

## 8. Веб-сервер

- Пакет: `nginx` из репозитория Ubuntu (не собирается из исходников). Установка: `sudo apt update && sudo apt install -y nginx`.
- Конфигурация ресурса: `/etc/nginx/sites-available/devops-site`. Включена ссылкой `/etc/nginx/sites-enabled/devops-site`. Ссылка на стандартный ресурс `/etc/nginx/sites-enabled/default` удалена, файл в `sites-available` сохранён.
- Каталог ресурса: `/var/www/devops-site`, владелец `devops:devops`. Каталог `755`, файлы `644`. Эти права выставляет доставка: `rsync -avz --delete --chmod=D755,F644`.
- HTTP (порт 80) отвечает `301` на `https://$host$request_uri`. HTTPS слушает 443, протоколы TLSv1.2 и TLSv1.3. Заголовок HSTS не задаётся.
- Сертификат: `/etc/ssl/certs/devops.crt`, права `644`, владелец `root`. Закрытый ключ: `/etc/ssl/private/devops.key`, права `600`, владелец `root`. В сертификате SAN `DNS:devops.local`, срок 365 дней. Команда:

```
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
```

- Применение конфигурации: `sudo nginx -t && sudo systemctl reload nginx`. Порты 80 и 443 уже разрешены в UFW. Профиль `Nginx Full` не добавлять.
- Проверка с хоста: `curl --cacert ~/devops.crt -I https://devops.local`. Копия сертификата снимается так: `scp devops:/etc/ssl/certs/devops.crt ~/devops.crt`. Ключ с сервера не копируется.
