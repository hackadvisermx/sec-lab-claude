# Uso autorizado y modelo de responsabilidad

SecLab es una **estación de trabajo**. Te da las herramientas, un entorno
reproducible y una forma ordenada de guardar lo que haces. No decide por ti
contra qué las usas.

Esta página existe para decirlo una vez, con claridad, y no repetirlo en cada
cheatsheet del repositorio.

## Lo que SecLab hace y lo que no

**Sí hace:**

- Ejecutar las herramientas en un contenedor aislado, con límites de recursos.
- Mantener los servicios ligados a `127.0.0.1` salvo que tú decidas otra cosa.
- Impedir que tus secretos, configuraciones de VPN y datos de trabajo lleguen a
  Git por accidente.
- Negarse a arrancar con contraseñas de relleno o secretos vacíos.
- Aislar los targets vulnerables de prácticas en su propia red Docker, sin
  salida a Internet.

**No hace:**

- Comprobar contra qué objetivo lanzas una herramienta.
- Mantener listas de rangos permitidos ni bloquear tráfico.
- Pedirte que justifiques una operación antes de ejecutarla.

Los laboratorios externos —Hack The Box, TryHackMe, la VPN de un cliente— son
plataformas ajenas, con sus propios términos de servicio y su propia
autorización. **Quedan fuera del alcance del contenedor.** SecLab se conecta a
ellas y ahí termina su papel.

## La premisa

Se da por supuesto que quien ejecuta SecLab tiene permiso para usar todas las
herramientas que incluye contra los objetivos que elija. Esa premisa es
responsabilidad de quien lo ejecuta.

En el contexto de este curso: **el riesgo es de cada estudiante, bajo la guía
del profesor**. Si tienes dudas sobre si algo entra dentro de lo que puedes
hacer, pregunta antes de hacerlo. Esa conversación es más barata que la
alternativa.

## Dónde mirar si no lo tienes claro

- **Hack The Box y TryHackMe** publican sus reglas de uso. Léelas una vez: te
  dicen qué está permitido dentro de sus redes, qué no (atacar la propia
  infraestructura de la plataforma, molestar a otros usuarios) y qué pasa si te
  las saltas.
- **Un cliente o un entorno corporativo** requiere autorización por escrito,
  con alcance y fechas. Sin ese documento no hay engagement, hay un delito.
- **Tu propia red, la del campus o la de tu casa** no son objetivos válidos
  sólo por ser tuyas o accesibles. Que puedas llegar a algo no significa que
  tengas permiso sobre ello.

## Lo que sigue siendo obligatorio

El hecho de que SecLab no vigile objetivos no relaja las medidas que te
protegen a ti y a tu máquina. Estas no son negociables y el software sí las
impone:

- Los servicios escuchan en `127.0.0.1`. Exponerlos requiere un cambio
  consciente en `.env`, y `seclab seguridad` te avisará.
- Ningún secreto, `.ovpn`, clave privada ni workspace llega a Git.
- No hay contraseñas por defecto. Si falta un secreto, SecLab no arranca.
- Los targets vulnerables corren en una red aislada y sin salida a Internet.
  Una máquina deliberadamente vulnerable expuesta a tu red es un problema real,
  no un ejercicio.
- Nada se borra sin confirmación explícita.

## Una nota sobre el asistente de IA

Si activas el servidor MCP (Fase 13), un agente de IA podrá invocar las
operaciones que estén en su lista blanca y todo quedará registrado en el log de
auditoría de tu workspace. Ese registro es para ti: para saber qué se hizo y
para tener material con el que redactar el informe. La lista blanca limita qué
puede hacer el agente, no contra qué. Sigue aplicando todo lo de esta página.
