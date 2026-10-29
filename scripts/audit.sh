#!/usr/bin/env bash
set -uo pipefail
PASS=0; FAIL=0
check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"; ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"; ((FAIL++))
    fi
}
echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
echo "[1] Служба SSH"
check "Вход от имени root запрещён"        "no"  "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no"  "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"
port="$(sudo sshd -T | awk '/^port /{print $2}')"
if [[ "$port" == "22" ]]; then
    check "Порт службы SSH отличен от 22" "не 22" "$port"
else
    check "Порт службы SSH отличен от 22" "$port" "$port"
fi
check "Лимит попыток аутентификации равен 3" "3" "$(sudo sshd -T | awk '/^maxauthtries /{print $2}')"
echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
check "Политика входящего трафика по умолчанию — deny" "deny" "$(sudo ufw status verbose | awk '/Default:/{print $2}')"
echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd
echo "[4] Веб-сервер"
check "Служба nginx активна" "active" "$(systemctl is-active nginx || true)"
if sudo nginx -t >/dev/null 2>&1; then
    nginx_syntax="0"
else
    nginx_syntax="1"
fi
check "Конфигурация nginx синтаксически корректна" "0" "$nginx_syntax"
if sudo openssl x509 -checkend $((30 * 24 * 3600)) -noout -in /etc/ssl/certs/devops.crt >/dev/null 2>&1; then
    cert_ok="yes"
else
    cert_ok="no"
fi
check "Сертификат действителен ещё не менее 30 дней" "yes" "$cert_ok"
writable="$(sudo find /var/www/devops-site -perm -o+w -print | wc -l | tr -d '[:space:]')"
check "В каталоге ресурса нет файлов, доступных для записи всем" "0" "$writable"
check "Права закрытого ключа равны 600" "600" "$(sudo stat -c '%a' /etc/ssl/private/devops.key)"
echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
