# Seguridad

## Alcance

SecLab protege **la máquina y los datos de quien lo ejecuta**. No supervisa ni
restringe contra qué objetivos se usan las herramientas que incluye: eso queda
fuera de su alcance y es responsabilidad de quien lo ejecuta. Ver
[docs/uso-autorizado.md](docs/uso-autorizado.md).

Un problema de seguridad en SecLab es algo que pone en riesgo al usuario: un
secreto que se filtra, un servicio que queda expuesto sin que se pida, un
privilegio concedido de más, un target vulnerable que sale de su red aislada.

## Garantías que el software impone

| Garantía | Cómo se impone | Estado |
|---|---|---|
| Los servicios escuchan en `127.0.0.1` | `SECLAB_BIND` y revisión de Compose | Fase 1 |
| Sin contraseñas por defecto | Se rechazan secretos vacíos, cortos o de relleno | Fase 1 |
| Secretos fuera de Git | `.gitignore` + comprobación de archivos versionados | Fase 1 |
| Configuraciones de VPN fuera de Git | `vpn/` ignorado; sólo se versionan plantillas | Fase 1 |
| Sin privilegios innecesarios | `cap_drop: ALL`, `no-new-privileges` | Fase 1 |
| Varias instancias sin colisión | `SECLAB_PROJECT`, sin `container_name` | Fase 1 |
| Permisos estrictos en archivos sensibles | Comprobación de `.env` (600) y `vpn/` (700) | Fase 1 |
| SSH por llave, sin acceso root directo | `AuthenticationMethods publickey`, cuenta root bloqueada | Fase 2 |
| Secretos generados, no fijos | `seclab init` | Fase 2 |
| El contenedor aborta si falta configuración segura | Validación en el entrypoint | Fase 2 |
| Llaves de host propias de cada instalación | Se eliminan en el build y se generan al primer arranque | Fase 2 |
| Capacidades de red sólo en el servicio VPN | Override dedicado por perfil | Fase 7 |
| Killswitch si cae el túnel | Servicio de VPN | Fase 7 |
| Targets vulnerables sin salida a Internet | Red Docker interna | Fase 12 |
| Servidor MCP autenticado y sólo en localhost | Override `mcp` opt-in | Fase 13 |

## Comprobar tu instalación

```bash
./bin/seclab seguridad
```

Revisa cobertura de `.gitignore`, archivos sensibles versionados, secretos de
relleno, permisos, exposición de puertos, privilegios de los contenedores y
rastro de claves privadas o tokens. Sale con código 1 si encuentra un fallo.

Los avisos no hacen fallar la revisión: señalan cosas que aún no existen (`.env`
o `vpn/` antes de `seclab init`) o recomendaciones.

Los secretos se evalúan **según el servicio al que pertenecen**: uno vacío sólo
es un fallo si su servicio está habilitado. Exigir la clave de Tailscale a quien
no usa Tailscale sería ruido, y el ruido acaba enseñando a ignorar los avisos.
Un valor de relleno, en cambio, falla siempre: si está escrito, es que alguien
pensaba usarlo.

La CI de la Fase 8 añadirá ShellCheck, Hadolint, gitleaks y Trivy.

## Capacidades del contenedor

El contenedor de laboratorio arranca con `cap_drop: ALL` y recibe de vuelta
exactamente diez capacidades, cada una con su motivo anotado en
`docker-compose.yml`:

`CHOWN`, `DAC_OVERRIDE`, `FOWNER` (preparar el estado y el workspace),
`SETGID`, `SETUID`, `SYS_CHROOT`, `AUDIT_WRITE`, `KILL` (sshd y sudo),
`NET_RAW` y `NET_BIND_SERVICE` (nmap, ping, tcpdump, listeners en puertos
bajos).

**`NET_ADMIN` no está en esa lista.** Manipular interfaces y tablas de rutas es
competencia del servicio de VPN, que lo recibe en su propio override (Fase 7).

La imagen concede a nmap `cap_net_raw` y `cap_net_bind_service` como
capacidades de fichero, para que funcione sin `sudo`, y **el build comprueba que
ningún binario reclame una capacidad fuera del conjunto del contenedor**. Ese
invariante importa más de lo que parece: cuando un binario pide una capacidad
que no está en el conjunto delimitador, el kernel rechaza su ejecución por
completo, y la herramienta no arranca ni para imprimir su versión.

### Por qué no se activa `no-new-privileges`

Porque no cerraría nada y rompería el laboratorio. El perfil de entrenamiento
concede `sudo` sin contraseña al usuario del laboratorio: la escalada dentro del
contenedor ya es explícita y deliberada, así que `no_new_privs` no impide nada
que no esté permitido. A cambio, el kernel dejaría de aplicar las capacidades de
fichero, y nmap no arrancaría.

### Sobre el `sudo` sin contraseña

Es una decisión consciente para un entorno **local de entrenamiento**, donde el
alumno necesita instalar herramientas y manipular la pila de red durante la
práctica. Root dentro del contenedor no es root en tu máquina: sigue limitado a
las diez capacidades de arriba y al aislamiento de espacios de nombres de
Docker. Si algún día SecLab se despliega en un entorno compartido, esta es la
primera decisión que hay que revisar.

## Contraseñas y secretos

SecLab **no tiene contraseñas por defecto**. `.env.example` entrega los
secretos vacíos y `seclab init` los genera.

Se rechazan explícitamente:

- Valores vacíos.
- Valores de relleno conocidos: `change-this-password`, `changeme`, `cambiame`,
  `password`, `admin`, `secret`, `seclab`, `toor`, `kali`, `123456`.
- Cualquier secreto de menos de 16 caracteres.

Si un secreto no es válido, el arranque falla con un mensaje que dice qué
regenerar. No hay degradación silenciosa.

### El escritorio y code-server (perfil `desktop`)

Los servicios gráficos añaden dos superficies nuevas, y conviene saber
exactamente qué protege cada cosa:

| Servicio | Puerto | Publicado en | Autenticación |
|---|---|---|---|
| Página de bienvenida | 8080 | 127.0.0.1 | ninguna: no muestra nada privado |
| noVNC → escritorio | 6080 | 127.0.0.1 | contraseña de VNC |
| code-server | 8443 | 127.0.0.1 | contraseña, y rechaza la incorrecta |
| Servidor VNC (Xvnc) | 5901 | **no se publica** | contraseña; escucha con `-localhost` |

Tres cosas que no son obvias:

- **La contraseña de VNC se trunca a 8 caracteres.** Es una limitación del
  propio protocolo (`VncAuth`), no de SecLab: el secreto que genera `init` tiene
  32, y VNC usa los ocho primeros. La defensa real es que el puerto sólo se
  publica en `127.0.0.1` y que Xvnc escucha con `-localhost`, de modo que sólo
  noVNC —dentro del contenedor— puede conectarse a él.
- **Ningún servicio arranca sin su secreto.** Si el escritorio está activado y
  `SECLAB_VNC_PASSWORD` está vacía, el contenedor aborta con un mensaje que dice
  qué ejecutar. No hay modo «sin contraseña por esta vez»: un escritorio abierto
  en el puerto de un portátil de clase es exactamente lo que no debe pasar.
- **Un servicio activado que el perfil no trae también aborta el arranque.** Es
  preferible a quedarse `unhealthy` sin explicación, o a publicar un puerto que
  no responde.

La contraseña de code-server se le pasa por variable de entorno desde la
configuración que supervisor genera en cada arranque, que es de root y con
permisos `600`. No añade exposición —el secreto ya viaja como variable del
contenedor, visible con `docker inspect`— pero tampoco se deja legible de más.

Cambiar `SECLAB_BIND` publica todo esto en tu red. Es un cambio consciente, y
la revisión de seguridad (`seclab seguridad`) lo marca.

## Qué nunca aparece en la salida

Ni en logs, ni en mensajes del CLI, ni en la página de bienvenida, ni en
informes generados:

- Contraseñas y tokens (VNC, code-server, Jupyter, MCP).
- Claves de autenticación de Tailscale.
- Contenido de archivos `.ovpn` ni credenciales de VPN.
- La IP pública del usuario.

La IP asignada dentro del túnel sí se muestra: la necesitas para trabajar.

## Reportar un problema

Si encuentras un fallo de seguridad en SecLab, comunícalo al responsable de la
asignatura antes de hacerlo público. Incluye la versión (`seclab version`), tu
sistema operativo y los pasos para reproducirlo.
