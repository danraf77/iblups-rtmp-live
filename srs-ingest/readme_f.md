# Flujo de Procesos — Servidor Ingest IBLUPS

Este documento explica de manera sencilla cómo funciona el Servidor Ingest de IBLUPS ("La Puerta de Entrada") cuando un creador o usuario inicia una transmisión en vivo.

---

## 🎥 1. El Streamer Empieza a Transmitir
Todo comienza cuando el Streamer presiona el botón "Iniciar Transmisión" en su programa (por ejemplo, OBS Studio). El programa envía su video hacia nuestro servidor usando una dirección y su **`stream_key`** (una contraseña única).
* **Ejemplo del destino desde OBS:** `rtmp://ingest.iblups.com/live/<stream_key>`

## 🛑 2. Detención Temporal y Verificación
Nuestro motor de video (llamado **SRS**) recibe esa conexión pero inmediatamente la pone en "Pausa". En una fracción de segundo, le pregunta a nuestro sistema de validación (El **Backend Go**): _"Dime, ¿este `<stream_key>` es válido?"_

## 🕵️‍♂️ 3. Consulta a la Base de Datos
El **Backend Go** verifica en nuestra base de datos Maestra (**Supabase**):
1. **Verificar identidad:** Revisa que el `<stream_key>` exista y pertenezca a una cuenta real.
2. **Obtener o Generar Tokens Seguros:** Para proteger la clave privada del Streamer, nunca mostramos su `<stream_key>` original a la audiencia. En su lugar, utilizamos un alias temporal ultrasecreto, conocido como **Token**. 
   * _Si el canal transmíte por primera vez:_ El sistema crea nuevos tokens aleatorios e irrompibles.
   * _Si ya ha transmitido antes:_ El sistema usa los tokens de sesiones pasadas.
3. El Backend actualiza el estatus del canal de "Apagado" a "🟢 EN VIVO".

## 🛣️ 4. Autorización y Mapeo Despachador (Reenvío)
Una vez que el sistema verifica que todo es legal, el Backend Go le da **luz verde** al motor SRS y le dice: _"¡Publícalo, pero envía este video a nuestros Servidores Distribuidores ("HLS" y "Thumbnail") NO usando su `<stream_key>`, sino usando su **Token Seguro**!"_.
* Esto significa que internamente re-enrutas (haces forwarding) el video.

## 📺 5. El Video es Procesado y Visto
1. **Servidor HLS (VPS_HLS):** Convierte el video fluído para que las webs y aplicaciones puedan mostrar el video en bloques adaptativos en diferentes dispositivos sin interrupciones.
2. **Servidor Miniaturas (VPS_THUMBNAIL):** Toma una foto (frame) del video cada cierto tiempo para mostrar una vista previa del Stream.

## 🚪 6. El Streamer Termina su Transmisión
Cuando el Streamer detiene el video ("Finalizar Transmisión"), ocurre el proceso inverso:
1. El motor SRS le avisa al Backend Go que el usuario cerró su stream. 
2. El sistema actualiza la base de datos de "EN VIVO" a "🔴 APAGADO" y cierra el contador de duración del video. 

---
_¡A lo largo de todo esto, nuestro servidor de Ingest también recopila estadísticas de manera invisible cada 30 segundos! (CPU, Megabytes en tránsito e Información Sensible logueada en Supabase)_
