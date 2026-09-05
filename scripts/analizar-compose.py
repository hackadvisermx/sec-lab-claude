#!/usr/bin/env python3
"""Analiza la configuración resuelta de Docker Compose y avisa de riesgos.

Lee el JSON de `docker compose config --format json` por la entrada estándar.
Sale con código 1 si encuentra un problema; el detalle va a la salida estándar
para que el script de shell lo muestre tal cual.

Comprueba lo que protege la máquina del usuario:
  - puertos publicados fuera de localhost
  - contenedores privilegiados o con capacidades peligrosas
  - container_name fijo, que impediría varias instancias en la misma máquina
  - montajes del socket de Docker, que equivalen a root en el host
"""

import json
import sys

CAPACIDADES_PELIGROSAS = {"ALL", "SYS_ADMIN", "SYS_PTRACE", "SYS_MODULE", "DAC_READ_SEARCH"}
BINDS_LOCALES = {"127.0.0.1", "::1", "localhost"}

def main() -> int:
    try:
        config = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(f"      → No se pudo leer la configuración de Compose: {exc}")
        return 1

    problemas = []

    for nombre, servicio in (config.get("services") or {}).items():
        for puerto in servicio.get("ports") or []:
            host_ip = puerto.get("host_ip") or "0.0.0.0"
            if host_ip not in BINDS_LOCALES:
                problemas.append(
                    f"{nombre}: el puerto {puerto.get('published')} escucha en {host_ip}, "
                    f"no en localhost. Lo expone a tu red. Ajusta SECLAB_BIND=127.0.0.1."
                )

        if servicio.get("privileged"):
            problemas.append(
                f"{nombre}: usa privileged: true, que anula el aislamiento del contenedor."
            )

        peligrosas = CAPACIDADES_PELIGROSAS & {c.upper() for c in (servicio.get("cap_add") or [])}
        if peligrosas:
            problemas.append(
                f"{nombre}: añade capacidades peligrosas ({', '.join(sorted(peligrosas))}). "
                f"Concédelas sólo al servicio que realmente las necesita."
            )

        if servicio.get("container_name"):
            problemas.append(
                f"{nombre}: define container_name fijo, lo que impide ejecutar varias "
                f"instancias de SecLab en la misma máquina. Usa SECLAB_PROJECT."
            )

        if servicio.get("network_mode") == "host":
            problemas.append(
                f"{nombre}: usa network_mode: host, que elimina el aislamiento de red."
            )

        for volumen in servicio.get("volumes") or []:
            origen = volumen.get("source") if isinstance(volumen, dict) else str(volumen)
            if origen and "docker.sock" in origen:
                problemas.append(
                    f"{nombre}: monta el socket de Docker, lo que equivale a dar root "
                    f"en tu máquina al contenedor."
                )

    for problema in problemas:
        print(f"      → {problema}")

    return 1 if problemas else 0


if __name__ == "__main__":
    sys.exit(main())
