FROM alpine:latest

RUN apk update && apk add --no-cache bash curl wget grep

ARG TARGETARCH
ARG TARGETOS

RUN YQ_VERSION=$(curl -s https://api.github.com/repos/mikefarah/yq/releases/latest \
        | grep -oP '"tag_name": "\K(.*)(?=")') && \
    if [ "$(uname -m)" = "x86_64" ]; then PLATFORM="linux_amd64"; \
    elif [ "$(uname -m)" = "aarch64" ]; then PLATFORM="linux_arm64"; \
    elif [ "$(uname -m)" = "armv7l" ]; then PLATFORM="linux_arm"; \
    else echo "Unsupported architecture: $(uname -m)"; exit 1; fi && \
    wget https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_${PLATFORM} -O /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

RUN mkdir -p /etc/d2c

COPY d2c.sh /usr/local/bin/d2c.sh
RUN chmod +x /usr/local/bin/d2c.sh

ENTRYPOINT ["/usr/local/bin/d2c.sh"]