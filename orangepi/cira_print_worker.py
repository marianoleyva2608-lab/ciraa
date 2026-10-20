#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Worker de impresion CIRA para Orange Pi (Armbian/Debian/Ubuntu).

Pregunta al servidor de CIRA cada pocos segundos si hay etiquetas para esta
impresora y las manda a la Zebra conectada por USB (/dev/usb/lp0).
No necesita IP fija ni puertos abiertos: solo salida a internet.

Configuracion: /etc/cira-print.conf  (lo crea install.sh)
Solo usa la libreria estandar de Python 3.
"""
import configparser
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

VERSION = '1.0'
CONF = os.environ.get('CIRA_PRINT_CONF', '/etc/cira-print.conf')


def log(*a):
    print(time.strftime('%Y-%m-%d %H:%M:%S'), *a, flush=True)


def cargar_config():
    c = configparser.ConfigParser()
    if not c.read(CONF):
        sys.exit(f'No encuentro {CONF}. Corre install.sh primero.')
    s = c['cira']
    cfg = {
        'servidor': s.get('servidor', '').rstrip('/'),
        'token': s.get('token', ''),
        'impresora': s.get('impresora', ''),
        'dispositivo': s.get('dispositivo', '/dev/usb/lp0'),
        'intervalo': s.getfloat('intervalo', 2.0),
    }
    faltan = [k for k in ('servidor', 'token', 'impresora') if not cfg[k]]
    if faltan:
        sys.exit('Faltan datos en ' + CONF + ': ' + ', '.join(faltan))
    return cfg


def http(cfg, metodo, ruta, cuerpo=None, timeout=20):
    url = cfg['servidor'] + ruta
    datos = json.dumps(cuerpo).encode() if cuerpo is not None else None
    req = urllib.request.Request(url, data=datos, method=metodo, headers={
        'X-Print-Token': cfg['token'],
        'X-Worker-Version': VERSION,
        'Content-Type': 'application/json',
        'User-Agent': 'cira-print-worker/' + VERSION,
    })
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode() or '{}')


def imprimir(cfg, zpl):
    dev = cfg['dispositivo']
    if not os.path.exists(dev):
        raise RuntimeError(f'No se encuentra la Zebra en {dev} (revisa el cable USB y que este encendida)')
    with open(dev, 'wb', buffering=0) as f:
        f.write(zpl.encode('utf-8'))


def main():
    cfg = cargar_config()
    ruta_cola = '/api/cira/cola?impresora=' + urllib.parse.quote(cfg['impresora'])
    log(f'CIRA print worker {VERSION} | impresora={cfg["impresora"]} | servidor={cfg["servidor"]} | {cfg["dispositivo"]}')
    espera = cfg['intervalo']
    while True:
        try:
            resp = http(cfg, 'GET', ruta_cola)
            espera = cfg['intervalo']
            for t in resp.get('trabajos', []):
                try:
                    imprimir(cfg, t['zpl'])
                    log(f'Trabajo {t["id"]} impreso')
                    http(cfg, 'POST', f'/api/cira/cola/{t["id"]}', {'ok': True})
                except Exception as e:
                    log(f'Trabajo {t["id"]} fallo: {e}')
                    try:
                        http(cfg, 'POST', f'/api/cira/cola/{t["id"]}', {'ok': False, 'error': str(e)})
                    except Exception as e2:
                        log('No se pudo reportar el error:', e2)
        except urllib.error.HTTPError as e:
            if e.code == 401:
                log('Token invalido: revisa "token" en', CONF, 'y CIRA_PRINT_TOKEN en Easypanel')
            else:
                log(f'Servidor respondio {e.code}')
            espera = min(espera * 2, 60)
        except Exception as e:
            log('Sin conexion con el servidor:', e)
            espera = min(espera * 2, 60)
        time.sleep(espera)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        pass
