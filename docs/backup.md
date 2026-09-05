# Copias de seguridad y restauración

`seclab backup` guarda todo lo que hace falta para reconstruir tu laboratorio en
otra máquina, y `seclab restore` lo devuelve a su sitio. Una copia se verifica
sola en cuanto se crea: si no pasa la verificación, se borra en lugar de quedarse
en disco aparentando servir.

## Qué se guarda y qué no

| Entra en la copia | Por qué |
|---|---|
| `.env` | Tu configuración y los secretos generados. Sin él el laboratorio no arranca |
| `secretos/` | La llave SSH del laboratorio. Sin ella no puedes entrar |
| `vpn/` | Tus perfiles y tus `.ovpn` |
| `workspace/` | Tu trabajo: labs, notas y evidencias. Lo único irreemplazable |
| `home.tar` | El volumen del directorio personal: historial de shell, configuración y **llaves de host SSH** |

No entra la imagen del laboratorio: se reconstruye con `seclab image build` a
partir del repositorio, y pesa cientos de megas. Tampoco entran las propias
copias anteriores.

El directorio personal viaja como un `tar` dentro del `tar`. Suena raro, pero es
lo que conserva propietarios y permisos exactos: macOS y Windows no representan
igual los permisos de Unix, y una copia de archivos «plana» los perdería por el
camino. Las llaves de host van ahí dentro, y por eso restaurar una copia **no**
provoca el aviso de cambio de llave de SSH.

## Crear una copia

```bash
./bin/seclab backup
```

El laboratorio puede estar en marcha. Si tu workspace es enorme y sólo quieres
salvar la configuración:

```bash
./bin/seclab backup --sin-workspace
```

La copia queda en `backups/` con permisos `600` y su `.sha256` al lado.
`backups/` está en `.gitignore`: una copia **contiene secretos en claro**, así
que guárdala donde guardarías una contraseña.

Nada se borra automáticamente. Las copias antiguas se acumulan hasta que las
borres tú:

```bash
./bin/seclab backup list
```

## Verificar

```bash
./bin/seclab backup verify            # la más reciente
./bin/seclab backup verify ARCHIVO    # una en concreto
```

Comprueba cuatro cosas: que el `.sha256` coincide, que el `tar.gz` se puede
leer, que dentro están los archivos sin los que no se puede restaurar, y que el
tamaño no delata una copia vacía. También te recuerda si esa copia se hizo con
`--sin-workspace`, que es el error clásico: descubrir el día malo que la copia
no traía el trabajo.

## Restaurar

Hay dos modos y la diferencia importa.

### Modo seguro: extraer en otro sitio

```bash
./bin/seclab restore ARCHIVO --destino /ruta/nueva
```

Extrae la copia en un directorio nuevo y **no toca tu instalación**. Es lo que
quieres para inspeccionar una copia, para recuperar un solo archivo, o para
comprobar que una copia de verdad se puede restaurar sin arriesgar nada.
Acuérdate de borrar el directorio después: contiene `.env` y tu llave SSH.

### Modo en sitio: restaurar sobre esta instalación

```bash
./bin/seclab stop
./bin/seclab restore --reciente     # o: restore ARCHIVO
```

Antes de tocar nada verifica la copia, y luego:

- **Exige el laboratorio detenido.** Restaurar el directorio personal mientras
  sshd lo está usando dejaría el volumen a medias.
- **Pide confirmación**, con la lista de lo que va a reemplazar.
- **No borra lo que hay**: lo aparta a `<nombre>.previo-<fecha>`. Si te has
  equivocado de copia, tu estado anterior sigue ahí. Bórralos tú cuando hayas
  comprobado que todo está bien.
- **Ajusta los permisos** de `.env`, `secretos/` y `vpn/` al terminar: una copia
  extraída puede llegar con los permisos del sistema donde se creó.

El volumen del directorio personal es la excepción: ese **sí** se sobrescribe y
no tiene versión anterior. Está dicho en la confirmación.

Después:

```bash
./bin/seclab doctor
./bin/seclab start
```

## Llevarse el laboratorio a otra máquina

1. En la máquina vieja: `./bin/seclab backup`.
2. Copia el repositorio (o clónalo) y el archivo de `backups/` a la nueva.
3. En la nueva: `./bin/seclab init --sin-arrancar` para construir la imagen.
4. `./bin/seclab stop` si init la dejó arrancada, y `./bin/seclab restore ARCHIVO`.
5. `./bin/seclab start`.

La copia lleva tus llaves de host, así que tu cliente SSH no se quejará de nada.

## Qué no cubre esto

Una copia en el mismo disco que el laboratorio no es una copia de seguridad
frente a lo que de verdad pasa: que el disco muera o que el portátil se pierda.
Súbela a donde guardes tus trabajos de la asignatura, o cámbiala de destino:

```
SECLAB_BACKUP_DIR=/Volumes/USB/seclab-copias
```

Elige una ruta **fuera** del workspace. Si está dentro, la copia se incluiría a
sí misma y crecería en cada ejecución; SecLab lo detecta y se niega.
