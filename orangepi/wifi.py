#!/usr/bin/env python3
"""Agrega una red wifi a la Orange Pi (netplan) sin borrar las que ya tiene.

Uso:  sudo python3 wifi.py
Pregunta el nombre y la clave, arma /etc/netplan/30-wifi.yaml con todas las redes,
lo revisa con `netplan generate` y, si algo falla, regresa al archivo anterior.
"""
import getpass, glob, json, os, re, shutil, subprocess, sys

ARCHIVO = '/etc/netplan/30-wifi.yaml'
RESPALDO = '/root/30-wifi.respaldo'

if os.geteuid() != 0:
    sys.exit('Corre con sudo:  sudo python3 wifi.py')

# Archivos de netplan vacíos rompen todo ("expected mapping"): se quitan.
for f in glob.glob('/etc/netplan/*.yaml'):
    if f != ARCHIVO and not open(f).read().strip():
        os.remove(f)
        print('Quité archivo vacío:', f)

redes = {}
if os.path.exists(ARCHIVO):
    shutil.copy(ARCHIVO, RESPALDO)
    texto = open(ARCHIVO).read()
    # Formato en una línea: "RED": {password: "clave"}
    for m in re.finditer(r'"?([^"{},:\n]+?)"?\s*:\s*\{\s*password\s*:\s*("([^"]*)"|([^}\s]+))\s*\}', texto):
        redes[m.group(1).strip()] = m.group(3) if m.group(3) is not None else m.group(4)
    # Formato en bloque:  "RED":\n   password: "clave"
    for m in re.finditer(r'^\s+"?([^"\n:]+?)"?\s*:\s*\n\s+password\s*:\s*"?([^"\n]*)"?\s*$', texto, re.M):
        redes[m.group(1).strip()] = m.group(2)
    for k in ('access-points', 'wlan0', 'wifis', 'network'):
        redes.pop(k, None)

print('Redes guardadas:', ', '.join(redes) or '(ninguna)')
ssid = input('Nombre del wifi nuevo [cirasegura]: ').strip() or 'cirasegura'
clave = getpass.getpass('Clave de %s (no se ve al escribir): ' % ssid)
if not 8 <= len(clave) <= 63:
    sys.exit('ERROR: la clave debe tener entre 8 y 63 caracteres (tiene %d). No cambié nada.' % len(clave))
redes[ssid] = clave

y = ('network:\n  version: 2\n  renderer: networkd\n  wifis:\n    wlan0:\n'
     '      dhcp4: true\n      access-points:\n')
for n, c in redes.items():
    y += '        %s:\n          password: %s\n' % (json.dumps(n), json.dumps(c))
with open(ARCHIVO, 'w') as f:
    f.write(y)
os.chmod(ARCHIVO, 0o600)

r = subprocess.run(['netplan', 'generate'], capture_output=True, text=True)
if r.returncode:
    if os.path.exists(RESPALDO):
        shutil.copy(RESPALDO, ARCHIVO)
    sys.exit('ERROR de netplan; dejé el wifi como estaba:\n' + r.stderr)

print('OK. Redes guardadas:', ', '.join(redes))
if input('¿Aplicar ahora? Si estás por SSH se puede cortar unos segundos [s/N]: ').strip().lower() in ('s', 'si', 'sí', 'y'):
    subprocess.run(['netplan', 'apply'])
    print('Aplicado.')
else:
    print('Se aplicará al reiniciar, o corre: sudo netplan apply')
