# Guía de Instalación en Servidor Limpio (Ubuntu 22.04)

Esta guía documenta los pasos exactos que un Administrador de Sistemas debe seguir al recibir un Servidor o VPS nuevo con **Ubuntu 22.04** limpio, para alojar cualquiera de los 3 nodos de la plataforma IBLUPS Live:
1. `srs-ingest` (Ingesta)
2. `srs-hls` (Transcodificación HLS Edge)
3. `srs-thumbnail` (Generación de Miniaturas)

---

## 🛠 Fase 1: Preparación del Sistema Operativo

Inicia sesión en tu servidor Ubuntu 22.04 vía SSH (`ssh root@TU_IP`) y ejecuta:

### 1. Actualizar dependencias
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl wget nano htop net-tools
```

### 2. Instalar Docker y Docker Compose
Añadimos las claves oficiales y el repositorio de Docker para Ubuntu:
```bash
# Agregar la GPG key oficial de Docker
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Añadir el repositorio a Apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update

# Instalar los paquetes de Docker
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Habilitar Docker para que inicie con el sistema
sudo systemctl enable docker
sudo systemctl start docker
```

### 3. Tuning de Alta Concurrencia P/ Streaming (Opcional pero Recomendado)
Para evitar que el servidor Linux tire conexiones bajo alta carga de miles de usuarios (Critical para VPS de +16 Cores), agrega estas variables al control del kernel:

```bash
cat <<EOF | sudo tee -a /etc/sysctl.conf
# Ajustes IBLUPS Streaming Networking
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
EOF

# Aplicar los cambios sin reiniciar
sudo sysctl -p
```

---

## 📦 Fase 2: Clonar y Desplegar el Repositorio

Clona el código en la carpeta de operadores sugerida (`/opt/`) o tu `/home/`:
```bash
cd /opt
git clone https://github.com/danraf77/iblups-rtmp-live.git
cd iblups-rtmp-live
```

### Elige tu NODO a desplegar:
Dependiendo de a qué servidor estás configurando, entra en su respectiva carpeta.

**(A) Si es el Servidor de INGESTA (Ingest):**
```bash
cd srs-ingest
cp .env.example .env
nano .env # (Agrega las claves de Supabase, las IPs del HLS/Thumb, y Resend)
docker compose up -d --build
```

**(B) Si es el Servidor HLS:**
```bash
cd srs-hls
cp .env.example .env
nano .env # (Ajusta la IP, el alerta y tu Resend API Key)
docker compose up -d
```

**(C) Si es el Servidor THUMBNAIL:**
```bash
cd srs-thumbnail
cp .env.example .env
nano .env # (Ajusta la IP, el alerta y tu Resend API Key)
docker compose up -d
```

---

## 🛡 Fase 3: Habilitar el Sistema Auto-Monitor (Systemd)

Para prevenir caídas "silenciosas" y asegurar que si un programa se traba, Linux lo recupere inmediatamente, instala el archivo de servicio (recuerda estar aún dentro de la carpeta del proyecto que elegiste en la Fase 2):

```bash
# Copia los archivos del timer y el servicio a Linux
sudo cp srs-monitor.service /etc/systemd/system/
sudo cp srs-monitor.timer /etc/systemd/system/

# Recarga el manejador de servicios
sudo systemctl daemon-reload

# Activa el temporizador (Inicia las revisiones del estado)
sudo systemctl enable --now srs-monitor.timer

# Para revisar que se instaló todo bien y el estatus actual ejecuta:
sudo systemctl status srs-monitor.timer
```

### ✅ ¡Tú sistema ahora está desplegado e Inmune a reinicios!
*(El VPS arrancará la red automáticamente y monitoreará el flujo por ti de por vida).*

---

## 🔄 Fase 4: ¿Cómo actualizar el código en el futuro?

Cuando hagas cambios en el repositorio de GitHub (ej. editar un conf, arreglar un script de Go) y necesites aplicarlos en el VPS que ya está corriendo en producción, simplemente sigue este proceso sin asustarte.

1. Entra a la carpeta raíz del proyecto y trae los cambios:
```bash
cd /opt/iblups-rtmp-live
# O usa la ruta donde lo hayas clonado
git pull origin main
```

2. Entra a la carpeta del nodo específico que cambiaste (por ejemplo, el de Ingesta) y reinicia su contenedor Docker para que absorba la nueva configuración:
```bash
cd srs-ingest

# Detiene el stack, lo reconstruye (vital si tocaste Go), y lo levanta
docker compose down
docker compose up -d --build
```
*(Repite el paso 2 entrando a `srs-hls` o `srs-thumbnail` si los cambios afectaban a esos nodos).*
