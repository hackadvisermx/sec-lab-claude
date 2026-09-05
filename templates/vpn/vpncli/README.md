# Perfil `vpncli` — VPN de cliente o engagement

Perfil pensado para el profesorado y para trabajo profesional: la VPN de un
cliente, un entorno corporativo o un engagement con autorización propia.

Coloca aquí (`vpn/vpncli/`) la configuración que te haya entregado la
organización correspondiente.

## Diferencias con `vpnhtb` y `vpntry`

Una VPN corporativa suele comportarse de forma distinta a la de una plataforma
de formación. Presta atención a dos cosas:

**Ruta por defecto.** Muchas VPN de empresa empujan `redirect-gateway`, es
decir, quieren llevarse *todo* tu tráfico. SecLab arranca OpenVPN con
`--route-nopull` y añade sólo los rangos que declares, precisamente para que eso
no ocurra sin que tú lo decidas. Si el acceso al entorno del cliente exige la
ruta por defecto, actívalo de forma explícita con `SECLAB_VPN_RUTA_DEFECTO=true`
y ten presente que a partir de ese momento todo tu tráfico sale por ahí.

**Autenticación.** Es frecuente que pidan usuario y contraseña además del
certificado, y a veces un segundo factor. Si tu `.ovpn` usa `auth-user-pass`,
apúntalo a un archivo de credenciales en este mismo directorio con permisos
`600`. Si hay segundo factor por token, la conexión no podrá automatizarse: es
una limitación del método, no de SecLab.

## Configuración

Copia `perfil.env.example` a `perfil.env` y ajústalo.

## Permisos

```
chmod 700 vpn/vpncli
chmod 600 vpn/vpncli/*
```

Las credenciales de un cliente merecen más cuidado que las de una plataforma de
formación. `vpn/` nunca entra en Git, pero conviene que tampoco acabe en una
copia de seguridad sincronizada a la nube sin cifrar.
