#!/usr/bin/env bash
# Instala el worker de impresion CIRA en una Orange Pi (Armbian/Debian/Ubuntu).
#
# Uso:
#   sudo bash install.sh <nombre-impresora> <token> [zebra|ticket] [servidor]
# Ejemplos:
#   sudo bash install.sh matriz MI_TOKEN_SECRETO            (Zebra, ZPL)
#   sudo bash install.sh caja   MI_TOKEN_SECRETO ticket     (térmica de tickets 58 mm)
set -euo pipefail

NOMBRE="${1:-}"
TOKEN="${2:-}"
TIPO="zpl"
SERVIDOR="https://pwa-ciraa.c4o2yg.easypanel.host"
for a in "${@:3}"; do
  case "$a" in
    ticket|tickets|escpos|58) TIPO="ticket" ;;
    zebra|zpl) TIPO="zpl" ;;
    http*) SERVIDOR="$a" ;;
  esac
done

if [[ $EUID -ne 0 ]]; then echo "Corre con sudo: sudo bash install.sh <nombre> <token>"; exit 1; fi
if [[ -z "$NOMBRE" || -z "$TOKEN" ]]; then
  echo "Uso: sudo bash install.sh <nombre-impresora> <token> [zebra|ticket] [servidor]"; exit 1
fi
NOMBRE="$(echo "$NOMBRE" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9_-')"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Python 3"
command -v python3 >/dev/null || { apt-get update && apt-get install -y python3; }

echo "==> Driver USB de impresora (usblp)"
modprobe usblp 2>/dev/null || true
grep -qx usblp /etc/modules 2>/dev/null || echo usblp >> /etc/modules

echo "==> Usuario de servicio cira-print (grupo lp)"
id cira-print >/dev/null 2>&1 || useradd --system --user-group --no-create-home --shell /usr/sbin/nologin --groups lp cira-print
usermod -aG lp cira-print

echo "==> Archivos"
install -d /opt/cira-print
install -m 755 "$DIR/cira_print_worker.py" /opt/cira-print/cira_print_worker.py
cat > /etc/cira-print.conf <<EOF
[cira]
servidor = $SERVIDOR
token = $TOKEN
impresora = $NOMBRE
dispositivo = /dev/usb/lp0
intervalo = 2
tipo = $TIPO
EOF
chown root:cira-print /etc/cira-print.conf
chmod 640 /etc/cira-print.conf
install -m 644 "$DIR/cira-print.service" /etc/systemd/system/cira-print.service

echo "==> Servicio"
systemctl daemon-reload
systemctl enable cira-print
systemctl restart cira-print
sleep 3
systemctl --no-pager --lines=8 status cira-print || true

echo
if [[ -e /dev/usb/lp0 ]]; then
  echo "OK: impresora detectada en /dev/usb/lp0"
else
  echo "AVISO: no veo /dev/usb/lp0. Conecta la impresora por USB, enciendela y revisa con: ls /dev/usb/"
fi
echo "Listo. Impresora '$NOMBRE' (tipo $TIPO) registrada contra $SERVIDOR"
echo "Ver registro en vivo: journalctl -u cira-print -f"
