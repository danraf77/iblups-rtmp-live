FROM ossrs/srs:6

# Cambiar a usuario root temporalmente para instalar ffmpeg
USER root

# Actualizar repositorios e instalar FFmpeg nativo de Linux
RUN apt-get update && \
    apt-get install -y ffmpeg && \
    rm -rf /var/lib/apt/lists/*

# Restaurar permisos o usuario si fuese necesario (opcional, SRS usualmente corre en root o srs)
