FROM caddy:builder AS builder

RUN xcaddy build \
    --with github.com/hslatman/caddy-crowdsec-bouncer/http \
    --with github.com/caddyserver/transform-encoder

FROM caddy:2.7-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
