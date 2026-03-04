FROM ossrs/srs:6

USER root

RUN apt-get update && \
    apt-get install -y ffmpeg && \
    rm -rf /var/lib/apt/lists/*

# Crear directorio objs que SRS necesita para el pid file
RUN mkdir -p /usr/local/srs/objs/nginx/html /usr/local/srs/objs/logs