# ==============================================================================
# 1. Frontend Build Stage (Node + pnpm)
# ==============================================================================
FROM node:lts-slim AS ui
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

RUN corepack prepare pnpm@latest --activate && corepack enable

WORKDIR /usr/src/yt-dlp-webui/frontend

# Copy package files first to leverage Docker layer caching
COPY frontend/package.json frontend/pnpm-lock.yaml* ./

# FIX: Force pnpm to completely skip or approve lifecycle script blocks inline
RUN pnpm install --frozen-lockfile --config.ignore-scripts=true

# Copy the rest of the frontend source and build
COPY frontend/ .
RUN pnpm run build

# ==============================================================================
# 2. Backend Build Stage (Go)
# ==============================================================================
FROM golang:alpine AS build 
RUN apk add --no-cache git

WORKDIR /usr/src/yt-dlp-webui

# Cache Go modules
COPY go.mod go.sum* ./
RUN go mod download

# Copy backend source and the compiled frontend from the 'ui' stage
COPY . .
COPY --from=ui /usr/src/yt-dlp-webui/frontend/dist /usr/src/yt-dlp-webui/frontend/dist

# Build static binary
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o yt-dlp-webui .

# ==============================================================================
# 3. Runtime Stage (Python + Dependencies)
# ==============================================================================
FROM python:alpine

# Combine everything into a single, optimized runtime installation layer
RUN apk add --no-cache ffmpeg ca-certificates curl wget gnutls && \
    pip install --no-cache-dir -U pip && \
    pip install --no-cache-dir --pre "yt-dlp[default,curl-cffi,mutagen,pycryptodomex,phantomjs,secretstorage]"

WORKDIR /app

# Copy only the compiled binary from the Go build stage
COPY --from=build /usr/src/yt-dlp-webui/yt-dlp-webui /app/yt-dlp-webui

VOLUME /downloads /config
EXPOSE 3033

ENTRYPOINT [ "./yt-dlp-webui", "--out", "/downloads", "--conf", "/config/config.yml", "--db", "/config/local.db" ]
