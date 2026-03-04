# IBLUPS Live Streaming Infrastructure

Este repositorio contiene la arquitectura completa de Streaming para **IBLUPS**, separada físicamente en 3 servicios que vivirán en distintos VPS por motivos de rendimiento y aislamiento:

## Estructura de Proyectos

### 1. 🚪 `srs-ingest/` (Punto de Ingesta)
Es la puerta de entrada para todos los Streamers. Recibe la señal RTMP (desde OBS/vMix) en el puerto `1935`. 
- **Funciones:** Genera y valida tokens seguros consultando Supabase, monitorea conexiones en tiempo real.
- **Transcodificación:** Ninguna. Reenvía de forma nativa la señal usando *Dynamic Forward* hacia HLS y Thumbnail.
- *Contiene toda la documentación previamente explicada sobre el servicio Go y SRS.*

### 2. 📺 `srs-hls/` (Origen HLS)
Responsable del procesamiento de la señal cruda que envía el Ingest. 
- **Funciones:** Empaquetar el flujo RTMP en HLS (archivos `.m3u8` y `.ts`). Se conecta a la CDN (ej. Cloudflare) para distribuir el video de manera masiva a los espectadores sin ahogar el ancho de banda del VPS.

### 3. 🖼️ `srs-thumbnail/` (Procesador de Miniaturas)
Un servicio dedicado exclusivamente a generar las previsualizaciones de video (imágenes estáticas) para mostrar en el feed o la grilla del Dashboard.
- **Funciones:** Realiza captura de frames (generalmente cada x segundos vía FFmpeg) del stream que recibe. Libera al Ingest y al HLS del trabajo costoso de decodificar video para imágenes.

---
> *Nota: Entra a cada carpeta para ver las instrucciones y archivos `.env` respectivos de cada módulo.*
