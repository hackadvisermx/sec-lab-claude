# CI/CD, supply chain y firma de imágenes

> Estado: pipeline de GitHub Actions escrito y verificado localmente (sintaxis
> y, donde ha sido posible, ejecución real de cada paso individual en esta
> máquina). Como el repositorio no tiene todavía ningún remoto de Git
> configurado, **el pipeline en sí no se ha ejecutado ni una vez en un runner
> real de GitHub Actions**. Ver `TESTING_GAPS.md`, sección "Fase 8", para el
> detalle exacto de qué se comprobó de verdad y qué queda pendiente de un
> runner real.

## Qué corre y cuándo

Dos workflows, en `.github/workflows/`:

| Workflow | Se dispara con | Qué hace |
|---|---|---|
| `ci.yml` | Cualquier push a cualquier rama (excepto tags `v*`) y cualquier pull request. También como workflow reusable (`workflow_call`), invocado por `publicar.yml`. | Toda la validación: estilo, seguridad, build, smoke tests, VPN. Nunca publica nada. |
| `publicar.yml` | Un push de tag `v*`. También manualmente (`workflow_dispatch`), con la opción `incluir_full_msf` para publicar además ese perfil. | Ejecuta `ci.yml` completo como puerta de entrada y, sólo si pasa, construye multi-arch, escanea, genera SBOM, firma y publica en GHCR. |

Un push normal a una rama **nunca publica una imagen**: sólo un tag `v*` lo
hace (o el disparo manual explícito). Esto es literal al requisito de
`prompt_v3.md` ("Publicación sólo desde tags versionados") y a lo que ya hace
`bin/seclab image publish` (`cmd_image_publish`) para una publicación local:
no publica nada si falla el manifiesto de herramientas, la revisión de
seguridad o los smoke tests. `publicar.yml` traslada esa misma garantía al
pipeline de CI, con `needs: verificar` como puerta: GitHub Actions no continúa
con un job que depende de otro que falló.

### Jobs de `ci.yml`

| Job | Qué comprueba | Bloqueante |
|---|---|---|
| `shellcheck` | `bash -n`/`sh -n` sobre todos los scripts de shell, y ShellCheck de verdad sobre `bin/seclab`, `lib/*.sh`, `scripts/*.sh` (incluido `scripts/ci/*.sh`), `docker/*.sh`, `docker/shell/*.sh` | Sí |
| `hadolint` | `docker/Dockerfile`. Se ignoran `DL3008`/`DL3009` (fijar versión de paquetes apt): la política del proyecto (`docs/politica-herramientas.md`) es fijar por checksum sólo las herramientas ofensivas de evolución rápida instaladas fuera de apt; el resto sigue el LTS de Ubuntu | Sí |
| `compose-validate` | `docker compose config` sobre las combinaciones reales de `docker-compose.yml` + `docker-compose.desktop.yml` + `docker-compose.vpn.yml`, y `docker buildx bake --print` de los cuatro perfiles | Sí |
| `gitleaks` | Escaneo de secretos de todo el historial con la action oficial de gitleaks | Sí |
| `terraform` | Si existe `terraform/`: `terraform fmt -check` y `terraform validate`. Si no existe (Fases 10-11, sin implementar todavía): el job pasa con un aviso explícito de que no hay nada que validar — nunca finge haber comprobado algo que no existe | Sí (cuando aplica) |
| `seguridad` | `scripts/verificar-seguridad.sh` contra un `.env` efímero generado por `scripts/ci/preparar-env.sh` | Sí |
| `build-test` (matriz `lite`/`desktop`/`full`) | `seclab image build` + `seclab start` + `scripts/smoke.sh` contra un contenedor real, en un runner efímero de GitHub; después, escaneo de la imagen con Trivy (`CRITICAL,HIGH`, informativo, no bloquea la rama) | El build y los smoke tests sí; Trivy aquí es sólo informativo (ver más abajo por qué en publicación sí bloquea) |
| `vpn-test` | `scripts/ci/probar-vpn.sh`: reproduce el procedimiento completo de la Fase 7 contra un servidor OpenVPN local de prueba (arranque de perfil, rutas exactas, rechazo por solape, killswitch) | Sí |

`full-msf` no entra en la matriz de `build-test`: es el perfil más pesado de
construir (Metasploit) y no aporta cobertura adicional relevante sobre el
manifiesto de herramientas o los smoke tests que no cubra ya `full` (mismo
Dockerfile, misma cadena de etapas). Se construye y publica sólo bajo demanda
(ver más abajo).

### Jobs de `publicar.yml`

1. **`verificar`** — invoca `ci.yml` entero como workflow reusable
   (`uses: ./.github/workflows/ci.yml`). Si cualquiera de sus jobs falla,
   ningún job posterior se ejecuta.
2. **`build-publish`** (matriz `lite`/`desktop`/`full`) — con QEMU
   (`docker/setup-qemu-action`) y Buildx, construye y publica en GHCR para
   `linux/amd64` y `linux/arm64` a la vez con `docker/build-push-action`
   (`provenance: true`), etiqueta con la versión del tag (`vX.Y.Z` → `X.Y.Z`),
   con el commit corto y como `latest`. Después:
   - Escanea la imagen publicada con Trivy — **aquí sí bloqueante para
     `CRITICAL`** (`exit-code: 1`): informar tras publicar no sirve de nada,
     hay que impedir la publicación.
   - Genera un SBOM con Syft (SPDX JSON) y lo adjunta a la imagen con
     `cosign attach sbom`.
   - Firma la imagen y el SBOM adjunto con Cosign, en modo **keyless** (OIDC
     de GitHub Actions: `permissions: id-token: write`, sin ninguna clave
     privada que gestionar ni rotar).
   - Sube el SBOM también como artefacto descargable del workflow.
3. **`build-publish-full-msf`** — idéntico procedimiento, pero **sólo se
   ejecuta si se dispara manualmente el workflow con `incluir_full_msf: true`**
   (`workflow_dispatch`). Un push de tag normal nunca lo activa. Igual que
   `docker-bake.hcl` mantiene `full-msf` fuera del grupo `todos`, la
   publicación lo mantiene fuera de la publicación automática por tag.

## Política de firma y verificación

**Cosign, keyless, con el emisor OIDC de GitHub Actions**
(`https://token.actions.githubusercontent.com`). No hay clave privada de
firma que generar, guardar como secreto de repositorio ni rotar: la identidad
firmante es el propio workflow de GitHub Actions (repositorio + ref + evento),
certificada por Sigstore/Fulcio en el momento de la firma y registrada en el
log público de transparencia de Rekor.

Verificar una firma keyless exige comprobar **contra qué identidad exacta**
se firmó — verificar sin fijar la identidad equivaldría a aceptar la firma de
cualquier workflow de cualquier repositorio. Por eso `seclab image verify`
(`cmd_image_verify` en `bin/seclab`) exige `SECLAB_COSIGN_IDENTIDAD_REGEX` en
`.env` y aborta con instrucciones si falta, en vez de fingir una verificación
sin sentido. El valor que corresponde a este pipeline, una vez el repositorio
tenga un remoto real, es:

```
SECLAB_COSIGN_IDENTIDAD_REGEX=^https://github\.com/TU-ORGANIZACION/TU-REPO/\.github/workflows/publicar\.yml@refs/tags/v.*$
SECLAB_COSIGN_EMISOR=https://token.actions.githubusercontent.com
```

Sustituye `TU-ORGANIZACION/TU-REPO` por el repositorio real del curso.

Para verificar una imagen ya publicada:

```
seclab image verify --imagen ghcr.io/TU-ORGANIZACION/TU-REPO/seclab-lite:X.Y.Z
```

`cosign` no está instalado en esta máquina de desarrollo: `cmd_image_verify`
ya está escrito para no fingir una verificación que no puede hacer (aborta
con instrucciones de instalación si el binario no existe). No se ha podido
ejecutar `cosign verify` de verdad en esta sesión; queda documentado como no
verificado en `TESTING_GAPS.md`.

## Registry

Sin `SECLAB_REGISTRY` configurado en `.env`, `bin/seclab` usa
`localhost:5000` (un registry Docker local de pruebas, para desarrollo y para
`seclab image publish` manual sin credenciales de nadie:
`docker run -d -p 5000:5000 --name registro-local registry:2`). El pipeline
de CI publica en **GHCR** (`ghcr.io/<owner>/<repo>/seclab-<perfil>`),
autenticado con el `GITHUB_TOKEN` efímero del propio workflow (`packages:
write`) — no hace falta ningún secreto adicional para publicar desde GitHub
Actions.

## SBOM y procedencia

- **Procedencia (provenance)**: generada automáticamente por
  `docker/build-push-action` con `provenance: true`, siguiendo el formato de
  atestación de BuildKit/SLSA. Queda adjunta a la imagen publicada como
  atestación OCI, verificable con `cosign verify-attestation` o
  `docker buildx imagetools inspect`.
- **SBOM (Software Bill of Materials)**: generado por separado con
  [Syft](https://github.com/anchore/syft) (la action oficial
  `anchore/sbom-action`), en formato SPDX JSON, y adjuntado a la imagen con
  `cosign attach sbom` — y firmado también, para que el SBOM en sí no pueda
  sustituirse sin invalidar la firma. Se decidió generarlo aparte en vez de
  con `sbom: true` de `build-push-action` (que produce un SBOM más limitado,
  derivado sólo de las capas de BuildKit) precisamente porque Syft entiende
  paquetes de apt, pip, gems y binarios descargados sueltos — más
  representativo del contenido real de la imagen de SecLab, que mezcla los
  tres.

## Escaneo de imágenes (Trivy)

Se usa la action oficial `aquasecurity/trivy-action`. En `ci.yml`
(`build-test`) el escaneo es informativo (`exit-code: 0`): sirve para ver la
tendencia de vulnerabilidades en cada PR sin bloquear el desarrollo normal por
un CVE nuevo en una dependencia de sistema que todavía no se ha podido fijar.
En `publicar.yml` el mismo escaneo **sí bloquea la publicación** si aparece
algo `CRITICAL` (`exit-code: 1`): es la última puerta antes de que la imagen
llegue a un alumno.

Trivy no está instalado en esta máquina de desarrollo; no se ha podido
ejecutar localmente. Sólo se ha validado la sintaxis de los pasos que lo
invocan.

## Cómo reproducir cada verificación en local

| Verificación de la CI | Cómo reproducirla en tu máquina |
|---|---|
| ShellCheck / sintaxis de shell | `make lint` (con `shellcheck` instalado; si no, sólo corre `bash -n`/`sh -n`, que ya cubre todos los scripts) |
| Hadolint | `make lint` (con `hadolint` instalado; si no, se omite con un aviso) |
| Validación de Compose y de `docker-bake.hcl` | `make lint` |
| gitleaks | `gitleaks detect --source . -v` (necesita `gitleaks` instalado) |
| terraform fmt/validate | No aplica todavía: no existe `terraform/` (Fases 10-11) |
| Revisión de seguridad | `make seguridad` (`scripts/verificar-seguridad.sh`) |
| Build + smoke test de un perfil | `seclab image build --profile <perfil> && seclab start --profile <perfil> && make smoke` |
| Test de VPN | `scripts/ci/probar-vpn.sh` — **ejecútalo siempre sobre una copia física aislada del repositorio en otro directorio, nunca sobre tu checkout de desarrollo real**: el script asume un checkout efímero (por eso `scripts/ci/preparar-env.sh` aborta si ya existe un `.env`), pero esa es una única capa de protección y el script termina con `docker compose ... down --volumes` sobre el proyecto configurado. Ver la advertencia completa al principio de `scripts/ci/probar-vpn.sh` |
| Escaneo de imágenes | `trivy image seclab-<perfil>:<version>-<commit>` (necesita `trivy` instalado) |
| SBOM | `syft <imagen> -o spdx-json=sbom.json` (necesita `syft` instalado) |
| Firma / verificación | `seclab image publish` / `seclab image verify` (necesitan `cosign` instalado; `publish` además necesita un registry accesible) |

## Publicación multi-arquitectura local (fuera de CI)

`docker-bake.hcl` ya documenta el camino manual:

```
docker buildx bake lite            # sólo tu arquitectura, para desarrollo
docker buildx bake lite-multiarch --push   # multi-arch real: sólo con
                                            # emulación QEMU configurada y
                                            # credenciales de un registry;
                                            # en la práctica, sólo desde CI
```

## Limitaciones conocidas y simplificaciones deliberadas

- **Las actions de terceros se referencian por etiqueta de versión (`@v4`,
  `@v3`, `@v6`, `@v0`, `@0.29.0`...), no por SHA de commit.** Fijar por SHA es
  más estricto contra un compromiso del propio Marketplace de Actions, pero
  esta máquina no tiene acceso para resolver y verificar los SHA exactos de
  cada action en el momento de escribir este documento. Se deja anotado como
  endurecimiento futuro, no como promesa incumplida.
- **`full-msf` nunca se construye ni publica automáticamente**, ni en
  `ci.yml` ni por defecto en `publicar.yml`: decisión deliberada por coste de
  build y por ser el perfil con la superficie legal/ética más sensible
  (Metasploit). Se publica sólo con `workflow_dispatch` y
  `incluir_full_msf: true`.
- **El test de VPN de la CI (`scripts/ci/probar-vpn.sh`) corre en un runner
  efímero de GitHub, nunca en la máquina de un alumno ni de quien mantiene el
  curso**: es autocontenido (crea su propio `.env`, su propio servidor OpenVPN
  de prueba local, su propia red Docker) y se destruye con el runner. Aun así,
  el script lleva su propia limpieza (`trap EXIT`) para no depender de que el
  runner lo haga por él.
