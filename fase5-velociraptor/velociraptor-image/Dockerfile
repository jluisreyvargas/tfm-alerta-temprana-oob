FROM debian:bookworm-slim

ARG VELOX_VERSION=0.76.6

RUN apt-get update && apt-get install -y curl ca-certificates --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sL \
  "https://github.com/Velocidex/velociraptor/releases/download/v${VELOX_VERSION}/velociraptor-v${VELOX_VERSION}-linux-amd64" \
  -o /usr/local/bin/velociraptor \
  && chmod +x /usr/local/bin/velociraptor

WORKDIR /velociraptor

EXPOSE 8001 8889

ENTRYPOINT ["/usr/local/bin/velociraptor"]
CMD ["--config", "/velociraptor/server.config.yaml", "frontend"]