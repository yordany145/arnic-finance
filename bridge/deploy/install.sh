#!/usr/bin/env bash
# Instala los temporizadores como servicios de usuario (no requiere root).
set -euo pipefail
d="$HOME/.config/systemd/user"; mkdir -p "$d"
cp "$(dirname "$0")"/*.service "$(dirname "$0")"/*.timer "$d/"
systemctl --user daemon-reload
systemctl --user enable --now arnic-ingest.timer arnic-report-daily.timer arnic-report-weekly.timer
loginctl enable-linger "$USER" 2>/dev/null || true
systemctl --user list-timers 'arnic-*'
