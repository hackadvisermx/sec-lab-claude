# Perfil `vpntry` — TryHackMe

Coloca en este directorio (`vpn/vpntry/`) el archivo de configuración que
descargas de TryHackMe.

## Cómo obtener el archivo

1. Entra en tu cuenta de TryHackMe.
2. Ve a **Access** (el panel de conexión a la red).
3. Elige el tipo de red y la región del servidor.
4. Pulsa **Download My Configuration File** y mueve el `.ovpn` aquí, por
   ejemplo como `vpntry.ovpn`.

El archivo contiene tu credencial personal. No lo compartas ni lo subas a Git.

## Configuración

Copia `perfil.env.example` a `perfil.env` y ajusta la ruta del `.ovpn`. Los
rangos del ejemplo son orientativos: TryHackMe usa rangos distintos según la
sala y el tipo de red (las salas de red dedicada tienen los suyos). Conecta y
comprueba lo real con:

```
seclab vpn status
```

## Nota sobre las salas de red

Algunas salas de TryHackMe despliegan una red completa con varios equipos y
rangos propios. Cuando trabajes en una de ellas, añade su rango a
`SECLAB_VPN_RANGOS` o no tendrás ruta hasta las máquinas.

## Permisos

```
chmod 700 vpn/vpntry
chmod 600 vpn/vpntry/*
```
