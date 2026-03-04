# SRS Thumbnail Generator (Procesador de Miniaturas)

Este es el proyecto para el tercer VPS destinado de forma exclusiva a **recibir un stream y extraer fotogramas PNG**.

### ¿Cómo Funciona?
Está configurado para usar el bloque reservado `transcode` y `ffmpeg` de forma nativa por dentro de SRS. En la frecuencia definida (`-update 1` y `vf fps=1/10`), extrae un `frame` de video cada 10 segundos y sobrescribe el antiguo fotograma para presentarlo como imagen estática continua para la aplicación central sin corromper memoria.

## 🚀 Despliegue en el Servidor

1. **Requerimientos:**
   * Docker y Docker Compose instalados.

2. **Copiar y configurar variables:**
   ```bash
   cp .env.example .env
   ```

3. **Ejecutar el Generador:**
   ```bash
   docker compose up -d
   ```
   > El proceso requiere capacidad computacional ya que decodifica video a la par que avanza, la limitación impuesta al *80% de recursos* en `docker-compose.yml` previene que `ffmpeg` ahorque el Kernel y el sistema Linux.

4. **Instalar el Monitor de Alertas:**
   Para prevenir cortes silenciosos en el flujo crudo, activar en Linux:
   ```bash
   sudo cp srs-monitor.service /etc/systemd/system/
   sudo cp srs-monitor.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now srs-monitor.timer
   ```

## 🖼 ¿Cómo obtener una Imagen (Miniatura)?

Una vez en vivo, la Snapshot (Captura estática) procesada estará disponible para la red externa a través de NGINX en el puerto 80 estándar:
```text
http://<VPS_THUMB_IP>/live/<thumbnail_token>.png
```

---

## ☁️ Rendimiento y Precaché con Cloudflare CDN (Magia)

Servir imágenes de forma dinámica a millones de usuarios puede agotar un servidor rápidamente. Este proyecto tiene **NGINX preconfigurado para interactuar con Cloudflare**, inyectando una orden estricta de actualización *cada 5 Segundos*.

### ¿Cómo configurarlo en tu Panel de DNS?

1. En la pestaña DNS de Cloudflare, la IP pública del `VPS_THUMB` debe tener la **"Nube Naranja" (Proxied)** activada.
2. (Opcional, NGINX lo hace solo) En *Cache Rules*: Crear una regla:
   - *If URL contains `.png`* -> Set Cache level to *Cache Everything* y Edge Cache TTL a `5 segundos`.

### ¿Por qué 5 segundos?
¡Esto es el balance perfecto!
* Si 10,000 personas al mismo tiempo entran para ver los En Vivos en **1 segundo dado**, tu VPS no enterará del golpe; Cloudflare le mandará a la audiencia de forma gratuita la imagen en caché guardada temporalmente.
* Al pasar **5 segundos**, esa imagen caducará en Cloudflare, obligando a que la siguiente petición nueva baje nuevamente a tu VPS para pescar una previsualización *recién extraída*. Resultando en imágenes siempre animadas en el Feed para tu usuario pero con una economía asombrosa de procesamiento.
