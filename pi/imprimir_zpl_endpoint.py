# -*- coding: utf-8 -*-
# Endpoint para la Raspberry Pi (servicio zebra-print).
# Pega este bloque en el app.py de la Pi, junto a /imprimir, /imprimir-h60, etc.
# Recibe el ZPL ya armado por etiquetas-productos.html y lo manda tal cual a la Zebra.
#
# Despues:  sudo systemctl restart zebra-print

ZEBRA_DEV = '/dev/usb/lp0'          # misma Zebra USB que ya usa el servicio
ZPL_MAX_BYTES = 2 * 1024 * 1024     # limite de seguridad (2 MB)


@app.route('/imprimir-zpl', methods=['POST'])
def imprimir_zpl():
    data = request.get_json(silent=True) or {}
    zpl = (data.get('zpl') or '').strip()

    if not zpl.startswith('^XA') or not zpl.endswith('^XZ'):
        return jsonify({'ok': False, 'error': 'ZPL invalido (debe iniciar con ^XA y terminar con ^XZ)'}), 400
    if len(zpl.encode('utf-8')) > ZPL_MAX_BYTES:
        return jsonify({'ok': False, 'error': 'ZPL demasiado grande'}), 413

    try:
        with open(ZEBRA_DEV, 'wb') as impresora:
            impresora.write(zpl.encode('utf-8'))
        return jsonify({'ok': True})
    except Exception as e:
        return jsonify({'ok': False, 'error': 'No se pudo escribir en la Zebra: ' + str(e)}), 500
