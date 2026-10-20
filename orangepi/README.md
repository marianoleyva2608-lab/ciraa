# Orange Pi → Zebra (impresión CIRA)

Cada Orange Pi tiene una Zebra conectada por USB. La página de etiquetas deja los
trabajos en una cola en el servidor de CIRA, y cada Orange Pi recoge los suyos cada
2 segundos. No hace falta IP fija, abrir puertos ni certificados: solo internet.

## Una sola vez (servidor)
1. En Supabase → SQL Editor, correr `schema-impresion.sql`.
2. En Easypanel → pwa → ciraa → Environment, agregar `CIRA_PRINT_TOKEN=<una clave larga>` → Implementar.

## En cada Orange Pi (Armbian / Debian / Ubuntu)
```bash
git clone https://github.com/marianoleyva2608-lab/ciraa.git
cd ciraa/orangepi
sudo bash install.sh <nombre> <CIRA_PRINT_TOKEN>            # Zebra
sudo bash install.sh <nombre> <CIRA_PRINT_TOKEN> ticket     # térmica de tickets 58 mm (ESC/POS)
```
`<nombre>` identifica la impresora en la página (ej. `matriz`, `taller`, `sucursal-norte`).

## Revisar
- Estado: `systemctl status cira-print`
- Registro en vivo: `journalctl -u cira-print -f`
- Zebra detectada: `ls /dev/usb/` (debe aparecer `lp0`)
- Cambiar nombre/token/servidor: editar `/etc/cira-print.conf` y `sudo systemctl restart cira-print`
