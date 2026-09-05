# Laboratorios del workspace

Un **lab** es un directorio dentro de `workspace/` con una estructura fija y una
ficha que dice contra qué trabajas y con qué autorización. Sirve para tres
cosas: que las evidencias no acaben en el escritorio, que el informe salga casi
solo, y que una práctica se pueda repetir desde cero de forma idéntica.

Puedes tener **varios labs a la vez**. Cada uno es independiente.

## Crear uno

```bash
./bin/seclab lab create htb-forest --vpn vpnhtb
```

Queda así:

```text
workspace/htb-forest/
├── scope.txt          ficha: objetivo, autorización, rangos y límites
├── report.md          informe, con su esqueleto ya puesto
├── recon/
├── notes/
├── loot/
├── screenshots/
└── exploits/
```

El nombre tiene que ser un *slug*: sólo minúsculas, dígitos y guiones, hasta 64
caracteres, empezando y acabando por letra o dígito. La regla es estrecha a
propósito, porque ese nombre acaba siendo un directorio y parte de rutas dentro
y fuera del contenedor: un espacio o un acento ahí da problemas tres pasos
después, en otro sitio y sin relación aparente. Si te equivocas, SecLab te
propone la versión válida de lo que escribiste.

`--vpn` es opcional y anota en la ficha el perfil y sus rangos. Los rangos
salen de `vpn/<perfil>/perfil.env` si ya lo tienes, y si no de la plantilla,
marcados como ejemplo: los de Hack The Box cambian y cada producto usa los
suyos, así que confírmalos con `seclab vpn status` cuando conectes.

## Lo primero, la ficha

```bash
$EDITOR workspace/htb-forest/scope.txt
```

Rellena **objetivo y autorización** antes de lanzar nada. Para HTB o TryHackMe
la autorización son sus términos de servicio; para un cliente, el encargo por
escrito.

Que quede claro: `scope.txt` **no es un cortafuegos**. SecLab no lo lee para
decidir qué puedes hacer y no comprueba contra qué lanzas las herramientas. Es
tu cuaderno, y la responsabilidad es tuya — ver
[uso-autorizado.md](uso-autorizado.md).

## Trabajar dentro

```bash
./bin/seclab shell --lab htb-forest
```

Abre la shell directamente en `/workspace/htb-forest`. Y si el lab declara un
perfil de VPN que no es el activo, avisa antes de entrar: lo que no debe pasar
es lanzar un escaneo creyendo que va por el túnel de la plataforma cuando va
por tu red doméstica.

## Ver los que tienes

```bash
./bin/seclab lab list
```

| Columna | Qué dice |
|---|---|
| `VPN` | El perfil que declara la ficha |
| `CREADO` | La fecha que anotó `lab create` |
| `ARCHIVOS` | Evidencias del trabajo **en curso** (sin contar la ficha ni el informe) |
| `RONDAS` | Cuántas veces se ha reiniciado, y por tanto cuántos archivos hay guardados |

## Repetir una práctica desde cero

```bash
./bin/seclab lab reset htb-forest
```

Devuelve el lab a su estado inicial: informe nuevo desde la plantilla y
subdirectorios vacíos. **No borra nada**: lo anterior se aparta a
`_archivo/<fecha>/` dentro del propio lab, y la ficha se queda donde está
porque el objetivo y la autorización no cambian porque repitas la práctica.

Pide confirmación y dice exactamente qué va a mover.

Cuando existan los targets vulnerables (DVWA, Juice Shop, WebGoat y el target
de Active Directory, Fase 12), `lab reset` los devolverá también a su estado
inicial, que es lo que permite que toda la clase repita la misma práctica en las
mismas condiciones.

## Qué entra en las copias de seguridad

Todo el workspace, y por tanto todos tus labs con sus evidencias, entra en
`seclab backup`. Ver [backup.md](backup.md).
