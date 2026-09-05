# Perfil `vpnhtb` — Hack The Box

Coloca en este directorio (`vpn/vpnhtb/`) el archivo de configuración que
descargas de Hack The Box.

## Cómo obtener el archivo

1. Entra en tu cuenta de Hack The Box.
2. Abre el panel de conexión (**Connect to HTB**) y elige el producto que vayas
   a usar: *Machines*, *Starting Point*, *Pro Labs*, *Fortresses*… Cada uno tiene
   su propio servidor.
3. Elige el servidor de la región más cercana y el protocolo **OpenVPN (UDP o
   TCP)**.
4. Descarga el `.ovpn` y muévelo aquí, por ejemplo como `vpnhtb.ovpn`.

El archivo incluye tu certificado de cliente: **es una credencial personal**. No
lo compartas, no lo subas a Git y no lo pegues en un chat. `vpn/` está en
`.gitignore` precisamente por esto.

## Configuración

Copia `perfil.env.example` a `perfil.env` y ajusta la ruta del `.ovpn`. Los
rangos que trae el ejemplo son sólo eso: un punto de partida. Hack The Box los
cambia, y varían según el producto y el servidor. Después de conectar, mira lo
que negoció realmente el túnel:

```
seclab vpn status
```

y ajusta `SECLAB_VPN_RANGOS` con lo que veas ahí.

## Permisos

```
chmod 700 vpn/vpnhtb
chmod 600 vpn/vpnhtb/*
```

`seclab seguridad` te avisa si se quedan más laxos de la cuenta.
