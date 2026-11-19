# MemMachine for Railway: the official CPU image, pinned by version and digest,
# plus Caddy as a small API-key gate (MemMachine itself has no authentication).
# To update: bump the tags and digests below, add a CHANGELOG.md entry, merge to main.
FROM caddy:2.11.9@sha256:4851e54a46b206517c574821bb5cc67f170d2156041e9fbc4c9193b45e84a75b AS caddy

FROM memmachine/memmachine:v0.4.0-cpu@sha256:80535e8ad4cd60024740e4b58fa723fcbea49e5a5a7ddb072d0e7518def038a9

COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy
COPY Caddyfile /etc/caddy/Caddyfile
COPY --chmod=755 railway-start.sh /app/railway-start.sh

# MemMachine listens only on loopback; Caddy owns the public port ($PORT).
ENV MEMMACHINE_INTERNAL_PORT=8081 \
    MEMORY_CONFIG=/app/configuration.yml \
    XDG_DATA_HOME=/tmp/caddy-data \
    XDG_CONFIG_HOME=/tmp/caddy-config

EXPOSE 8080
CMD ["/app/railway-start.sh"]
