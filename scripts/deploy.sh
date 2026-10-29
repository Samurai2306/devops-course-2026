#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
LOCAL_DIR="$(git rev-parse --show-toplevel)/site/"

dry=()
if [[ "${1:-}" == "--dry-run" ]]; then
    dry=(--dry-run)
elif [[ $# -gt 0 ]]; then
    echo "неизвестный аргумент: $1" >&2
    exit 1
fi

if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "нет site/index.html, доставка отменена" >&2
    exit 1
fi

# Незафиксированные правки отслеживаются. Неотслеживаемые файлы отчётов в docs/ доставку не блокируют.
dirty="$(git status --porcelain --untracked-files=all | grep -v -E '^\?\? docs/' || true)"
if [[ -n "$dirty" ]]; then
    echo "есть незафиксированные изменения, доставка отменена" >&2
    exit 1
fi

rsync -avz --delete --chmod=D755,F644 "${dry[@]}" \
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
    "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

if [[ ${#dry[@]} -gt 0 ]]; then
    exit 0
fi

if ! curl -fsS --cacert "$CA_CERT" -o /dev/null "$SITE_URL"; then
    echo "ресурс недоступен: ${SITE_URL}" >&2
    exit 1
fi

git rev-parse --short HEAD
