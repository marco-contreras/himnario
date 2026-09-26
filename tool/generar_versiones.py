#!/usr/bin/env python3
"""Genera el manifiesto con la huella y el tamaño de cada hoja de himno.

La app lo compara con el que tiene guardado para saber qué hojas cambiaron.
GitHub Actions lo genera en cada publicación (ver .github/workflows/deploy.yml),
así que no hay que editarlo a mano: basta con reemplazar la imagen.

Uso: python3 tool/generar_versiones.py <carpeta_de_imagenes> <archivo_salida>
"""
import hashlib
import json
import sys
from pathlib import Path

carpeta, salida = Path(sys.argv[1]), Path(sys.argv[2])
archivos = {}
for imagen in sorted(carpeta.glob('*.webp')):
    datos = imagen.read_bytes()
    archivos[imagen.stem] = {
        'hash': hashlib.sha256(datos).hexdigest()[:12],
        'bytes': len(datos),
    }
if not archivos:
    sys.exit(f'No se encontraron imágenes .webp en {carpeta}')

version = hashlib.sha256(json.dumps(archivos, sort_keys=True).encode()).hexdigest()[:12]
salida.write_text(json.dumps({'version': version, 'archivos': archivos},
                             sort_keys=True, separators=(',', ':')))
print(f'{salida}: {len(archivos)} hojas, versión {version}')
