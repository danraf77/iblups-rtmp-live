# SRS HLS Server (Origen CDN)

Este es el proyecto para el segundo VPS correspondiente al **Servidor de Empaquetado HLS**.

Recibe los envíos (Webhooks *Dynamic Forwarding*) provenientes del Servidor Ingest y asimila la transmisión de video para partirla en trozos pequeños (`.ts`) y manifestos (`.m3u8`), los cuales son ideales para la distribución web mediante redes de entrega de contenido (CDN).

## 🚀 Despliegue en el Servidor

1. **Requerimientos:**
   * Docker y Docker Compose instalados.
   * Sistema Operativo configurado para alta concurrencia (`sysctl.conf`).

2. **Copiar y configurar variables:**
   ```bash
   cp .env.example .env
   ```
   *Edita las variables con Nano/Vim para establecer una integración a tu servicio de monitoreo/alertas.*

3. **Ejecutar el Clúster HLS:**
   ```bash
   docker compose up -d
   ```
   > Este contenedor funciona bajo el modo de red *"host"* para evadir los cuellos de botella del proxy interno de Docker y exprimir los 16 vCores y 16 GB de RAM de manera óptima y nativa.

4. **Monitoreo Automático:**
   Recuerda instalar el temporizador del monitor en el sistema operativo central (como root):
   ```bash
   sudo cp srs-monitor.service /etc/systemd/system/
   sudo cp srs-monitor.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now srs-monitor.timer
   ```

## 🔄 ¿Cómo se obtiene el video?

Una vez en vivo, se puede reproducir la señal conectándote al servidor web Nginx (por el puerto HTTP 80 estándar) que corre en conjunto con SRS:

```text
http://<VPS_HLS_IP>/<app>/<public_token>.m3u8
```

## ☁️ Integración NGINX + Cloudflare CDN

Para garantizar que el servidor HLS soporte decenas de miles de espectadores sin colapsar el VPS, hemos incorporado un contenedor `nginx:alpine` al ecosistema que funciona bajo el archivo `nginx.conf`. Este contenedor hace el *"heavy-lifting"* conectándose con Cloudflare a través de cabeceras estrictas de *Cache-Control*, apagando el ineficiente servidor HTTP interno de SRS.

### Configuración Obligatoria en tu cuenta Cloudflare:

1. **Proxy Activo:** En la pestaña DNS de Cloudflare, la IP pública del `VPS_HLS` debe tener la **"Nube Naranja" (Proxied)** activada.
2. **Desactivar Optimizaciones (¡Crítico!):** Cloudflare puede corromper los archivos `.m3u8` si intenta inyectar JS o minificarlos. Tienes que ir a tu zona de CF y crear una *Configuration Rule* para la ruta de tus videos (`*hls.tudominio.com/*`) donde debes desactivar explícitamente:
   - **Rocket Loader**: OFF
   - **Auto Minify (HTML/CSS/JS)**: OFF
   - **Brotli/Zstandard Compression**: Opcional, pero sugerido OFF para evitar latencia de compresión en las playlists.
3. **Cache Rules (Reglas de Caché):** 
   Aunque NGINX envía las cabeceras automáticamente, Cloudflare por defecto NO cachea archivos `.ts` ni `.m3u8` en todos sus planes. Debes crear un par de *Cache Rules*:
   - **Regla 1 (Segments .ts):** *If URL contains `.ts`* -> Set Cache level to *Cache Everything* y Edge Cache TTL a `1 mes`.
   - **Regla 2 (Playlists .m3u8):** *If URL contains `.m3u8`* -> Set Cache level a **Bypass Cache**. (La CDN de Cloudflare pasará de largo y pedirá siempre este archivo directo a tu VPS para evitar listas vencidas o desincronización).

> ⚠️ **Advertencia Legal de Cloudflare (TOS)**:
> Basado en la base de datos de conocimientos del ecosistema Cloudflare, servir grandes cantidades de video crudo (`.ts`) a través de los planes gratuitos o Pro de Cloudflare (proxy normal) roza la violación de su *Acuerdo de Términos de Servicio (Término 2.8 / Servicio de CDN)* sobre proporción de recursos no-HTML. Si excedes terabytes de tráfico, Cloudflare podría limitar o bloquear temporalmente tu zona.
> **Solución Oficial:** Si llegas a escalar y tener miles de usuarios, considera firmar un plan Cloudflare Enterprise o usar su producto dedicado **Cloudflare Stream**, o rutear el video a través de proveedores con egreso de ancho de banda gratuito o menos restrictivo.

4. **Reproductor:** El navegador cargará el player en la ruta segura de tu plataforma (ejemplo: `https://hls.tudominio.com/live/<token>.m3u8`).
