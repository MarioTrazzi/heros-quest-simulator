# Servidor dedicado do HeroQuest (Godot headless, sem exportar: roda o projeto direto).
#   docker build -t heroquest-server .
#   docker run -p 8765:8765 -v hq-data:/data heroquest-server
# PORT (porta do WebSocket) e HQ_DATA_DIR (onde ficam as salas) vêm do ambiente.
# Em hospedagens com HTTPS (Railway etc.) o cliente usa wss://<domínio>; o TLS
# fica no proxy da hospedagem, o servidor fala ws:// puro.
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.2
# amd64 (servidores comuns) ou arm64 (Mac com Apple Silicon, Graviton).
ARG TARGETARCH
RUN case "${TARGETARCH:-amd64}" in arm64) ARCH=arm64 ;; *) ARCH=x86_64 ;; esac \
	&& NAME=Godot_v${GODOT_VERSION}-stable_linux.${ARCH} \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates wget unzip libfontconfig1 \
	&& wget -q https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/${NAME}.zip \
	&& unzip -q ${NAME}.zip \
	&& mv ${NAME} /usr/local/bin/godot \
	&& rm ${NAME}.zip \
	&& apt-get purge -y wget unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY project.godot ./
COPY autoload autoload
COPY data data
COPY referencias/heroscribe referencias/heroscribe
COPY scenes scenes
COPY scripts scripts
COPY server server
# Registra as classes (class_name) uma vez na imagem.
RUN godot --headless --path /app --import || true

# Sem VOLUME: o Railway recusa a instrução (lá o volume é montado em /data pelo painel/CLI);
# local, o `docker run -v hq-data:/data` monta do mesmo jeito.
ENV PORT=8765 HQ_DATA_DIR=/data
EXPOSE 8765
CMD ["sh", "-c", "godot --headless --path /app -- --server"]
