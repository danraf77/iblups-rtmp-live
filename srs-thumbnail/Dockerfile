FROM ossrs/srs:6

USER root

# Optimize layer size and install curl for healthchecks
RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Crear directorio objs que SRS necesita para el pid file
RUN mkdir -p /usr/local/srs/objs/nginx/html /usr/local/srs/objs/logs