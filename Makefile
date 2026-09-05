# =============================================================================
# SecLab — atajos de desarrollo
# =============================================================================
# El Makefile es una comodidad; la interfaz real es bin/seclab.
# Todo lo que hay aquí delega en el CLI para que no existan dos verdades.
# =============================================================================

SECLAB := ./bin/seclab

.DEFAULT_GOAL := ayuda
.PHONY: ayuda init up down start stop restart status doctor shell open logs seguridad image image-info image-todos image-publish image-verify backup backup-verify lab-list update smoke lint version clean vpn-list vpn-status vpn-down

ayuda:            ## Muestra la ayuda del CLI
	@$(SECLAB) ayuda

version:          ## Versión de SecLab
	@$(SECLAB) version

init:             ## Prepara la máquina y arranca por primera vez
	@$(SECLAB) init

up:               ## Arranca el laboratorio (alias de start)
	@$(SECLAB) start

down:             ## Detiene el laboratorio (alias de stop)
	@$(SECLAB) stop

start:            ## Arranca el laboratorio
	@$(SECLAB) start

stop:             ## Detiene el laboratorio
	@$(SECLAB) stop

restart:          ## Reinicia el laboratorio
	@$(SECLAB) restart

status:           ## Estado de los servicios
	@$(SECLAB) status

doctor:           ## Diagnóstico del entorno
	@$(SECLAB) doctor

shell:            ## Shell dentro del laboratorio
	@$(SECLAB) shell

open:             ## Abre la página de bienvenida en el navegador
	@$(SECLAB) open

logs:             ## Registros del laboratorio y de sus servicios
	@$(SECLAB) logs

lab-list:         ## Labs del workspace
	@$(SECLAB) lab list

update:           ## Trae la versión nueva del curso y reconstruye
	@$(SECLAB) update

seguridad:        ## Revisión de seguridad de la configuración
	@$(SECLAB) seguridad

backup:           ## Copia de seguridad, verificada al crearla
	@$(SECLAB) backup

backup-verify:    ## Verifica la copia más reciente
	@$(SECLAB) backup verify

image:            ## Construye la imagen del perfil configurado
	@$(SECLAB) image build

image-info:       ## Metadatos y etiquetas de la imagen actual
	@$(SECLAB) image info

image-todos:      ## Construye lite, desktop y full (full-msf va aparte)
	@docker buildx bake todos

image-publish:    ## Publica el perfil configurado (falla si manifiesto/seguridad/smoke fallan)
	@$(SECLAB) image publish

image-verify:     ## Verifica la firma Cosign de la imagen configurada
	@$(SECLAB) image verify

vpn-list:         ## Perfiles de VPN conocidos y cuál está activo
	@$(SECLAB) vpn list

vpn-status:       ## Estado del perfil de VPN activo
	@$(SECLAB) vpn status

vpn-down:         ## Baja el perfil de VPN activo
	@$(SECLAB) vpn down

smoke:            ## Smoke tests contra el laboratorio en marcha
	@./scripts/smoke.sh

lint:             ## Validación estática de scripts y de Compose
	@echo "→ Validando sintaxis de shell"
	@bash -n bin/seclab
	@bash -n lib/comun.sh
	@bash -n scripts/verificar-seguridad.sh
	@bash -n scripts/smoke.sh
	@bash -n docker/desktop/xstartup
	@bash -n docker/shell/bienvenida.sh
	@bash -n docker/shell/servicios.sh
	@sh -n docker/verificar-capacidades.sh
	@sh -n docker/descargar-fijado.sh
	@bash -n lib/plataforma.sh
	@bash -n lib/docker.sh
	@bash -n lib/secretos.sh
	@bash -n lib/backup.sh
	@bash -n lib/labs.sh
	@bash -n lib/vpn.sh
	@bash -n docker/entrypoint.sh
	@bash -n docker/salud.sh
	@bash -n docker/generar-manifiesto.sh
	@bash -n docker/shell/seclab-vpn.sh
	@sh -n docker/shell/seclab-vpn-hook.sh
	@bash -n scripts/ci/preparar-env.sh
	@bash -n scripts/ci/probar-vpn.sh
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "→ shellcheck (--severity=error; los avisos de estilo preexistentes de fases anteriores no bloquean, ver docs/ci.md)"; \
		shellcheck --severity=error bin/seclab lib/*.sh scripts/*.sh scripts/ci/*.sh docker/*.sh docker/shell/*.sh; \
	else \
		echo "! shellcheck no está instalado; se omite (la CI de la Fase 8 lo ejecuta)"; \
	fi
	@if command -v hadolint >/dev/null 2>&1; then \
		echo "→ hadolint (--failure-threshold=error; los avisos DL4006/DL3025 preexistentes no bloquean, ver docs/ci.md)"; \
		hadolint --ignore DL3008 --ignore DL3009 --failure-threshold error docker/Dockerfile; \
	else \
		echo "! hadolint no está instalado; se omite (la CI de la Fase 8 lo ejecuta)"; \
	fi
	@echo "→ Validando docker-compose.yml"
	@docker compose config --quiet
	@echo "→ Validando docker-compose.yml + docker-compose.vpn.yml"
	@docker compose -f docker-compose.yml -f docker-compose.vpn.yml config --quiet
	@docker compose -f docker-compose.yml -f docker-compose.desktop.yml -f docker-compose.vpn.yml config --quiet
	@echo "→ Validando docker-bake.hcl"
	@docker buildx bake --print lite >/dev/null
	@docker buildx bake --print desktop >/dev/null
	@docker buildx bake --print full >/dev/null
	@docker buildx bake --print full-msf >/dev/null
	@echo "→ Validando scripts de Python"
	@python3 -m py_compile scripts/analizar-compose.py
	@echo "✓ Validación completada"

clean:            ## Borra contenedor, red y volúmenes (pide confirmación)
	@$(SECLAB) limpiar
