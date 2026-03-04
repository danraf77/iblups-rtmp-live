# IBLUPS Streaming Platform — Servidor Ingest

Este repositorio contiene la infraestructura y el backend del **Servidor Ingest** (Punto de Entrada) para el sistema de transmisiones en vivo (Live Streaming) de IBLUPS.

Su función principal es recibir todas las conexiones RTMP entrantes desde softwares como OBS Studio, autenticarlas mediante una validación con la base de datos (Supabase), y reenviarlas (Forwarding) a los clústeres de origen (HLS y Thumbnailing) de manera enmascarada para proteger el nombre real del canal (`stream_key`).

> **Nota Adicional:** Este servidor **NO** realiza transcodificación (no usa FFmpeg) y **NO** interactúa directamente con los usuarios finales ni la CDN.

---

## 🏗 Arquitectura y Componentes

El proyecto está diseñado para funcionar en un entorno de alto rendimiento y puede de procesar más de 200 streams concurrentes gracias al uso de *Host Networking* en Docker y concurrencia optimizada en Go.

**Componentes Principales:**

1. **SRS 6 (Simple Realtime Server)**
   * Actúa como el receptor RTMP (`:1935`).
   * Configurado para utilizar *Dynamic Forwarding* (reenvío inteligente sin recodificar), consultando al backend Go a dónde enviar la transmisión (Edge HLS o Thumbnail Server).

2. **Backend en Go (`backend-go/`)**
   * Un servidor HTTP ultraligero que maneja los Webhooks (`on_publish`, `on_unpublish`, `on_forward`) emitidos por SRS.
   * **Mapeo de Tokens:** En lugar de exponer el `stream_key` a lo largo de la CDN y la web, genera aleatoriamente tokens opacos hex de 40 caracteres (`public_token` y `thumbnail_token`). Estos tokens se guardan de forma persistente en **Supabase** (tabla `channels_channel`).
   * Valida colisiones e inserta de forma segura a través de la API REST usando un `service_role key`.

3. **Sistema de Prevención Systemd (`srs-monitor.*`)**
   * Un script en Bash (`srs-monitor.sh`) diseñado para ejecutarse nativamente en el Sistema Operativo (fuera de Docker) cada 1 minuto (vía `systemd timer`).
   * Revisa que el contenedor funcione, que el puerto responda, y si ocurre algún problema, notifica vía correo electrónico utilizando la API de **Resend**. Si falla repetidamente (x3), fuerza automáticamente un reinicio del stack de Docker para recuperación inmediata.

---

## 🔀 Flujo de Trabajo (Conexión de Stream)

1. En **OBS**, un usuario transmite hacia `rtmp://[VPS_IP]:1935/live/<stream_key>`.
2. **SRS** pausa la conexión e invoca al webhook en el Backend Go (`/api/on_publish`).
3. El **Backend Go** verifica en Supabase si `<stream_key>` pertenece a un canal válido.
   * Si sí, activa el estado "live".
   * Si no posee tokens de seguridad (una nueva cuenta), los genera y almacena.
4. **SRS** recibe autorización y procede al siguiente paso para enrutar el tráfico dictado por su configuración (se acciona la solicitud *Dynamic Forward* `/api/on_forward`).
5. El **Backend Go** le responde a SRS las nuevas rutas donde debedirá reenviar esta transmisión:
   * `rtmp://[VPS_HLS]:1935/live/<public_token>`
   * `rtmp://[VPS_THUMB]:1935/live/<thumbnail_token>`

---

## 🚀 Guía de Despliegue

Este sistema está diseñado para un VPS configurado con un SO Linux moderno (preferiblemente Ubuntu 20+).

### 1. Requerimientos Previos

* Instalación de Docker y Docker Compose.
* Migración SQL aplicada en tu proyecto de **Supabase** (usando el archivo `./txt/01_add_tokens_to_channels.sql`).
* VPS configurado y ajustado en `/etc/sysctl.conf` para alta concurrencia (`somaxconn`, `tcp_max_syn_backlog`, etc.).

### 2. Configurar Variables de Entorno

Copia el molde que hemos dejado preparado en `.env.example`:

```bash
cp .env.example .env
```
Edita `.env` con un editor de texto e ingresa la ruta de tus bases de datos, claves secretas REST de Supabase, API logs y destinos HLS para el Reenvío dinámico (Forwarding).

### 3. Levantar Infraestructura (Docker)

Sitúate en la misma carpeta donde reside `docker-compose.yml` e inicia los servicios asegurando que el build del backend en Go aplique primero:

```bash
docker compose up -d --build
```
> Con el flag de `network_mode: "host"`, no es necesario mapear los puertos usando `<host>:<container>`. Se vincularán directamente.

### 4. Habilitar Monitoreo y Autorecuperación

Copia los archivos systemd al directorio de control del OS para hacer persistentes las verificaciones:

```bash
sudo cp srs-monitor.service /etc/systemd/system/
sudo cp srs-monitor.timer /etc/systemd/system/
```
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now srs-monitor.timer
```

Una vez realizado, puedes ver el estatus o los logs del monitor usando:
`sudo systemctl status srs-monitor.timer`

---

## 🔧 Posibles Ajustes

1. **Tokens Duplicados:** La probabilidad de duplicar un Token Hex CSPRNG de 20 bytes (~160bits) es astronómicamente baja. Aún así, un bucle de reintento de 5 pasos existe en `stream_mapper.go` para combatir restricciones `UNIQUE` inesperadas en PostgreSQL.
2. **Seguridad Firewall:** Asegúrate que el puerto `1935` esté abierto en tu Ingress/Firewall (UFW / Controles de OVH). Todos los demás puertos, como `3000` o `1985`, deben estar protegidos y restringidos solo para conexiones que provengan del nodo actual o nodos de IBLUPS.
