# Stage 1
FROM infisical/cli:0.43.121 AS infisical

FROM docker:cli

COPY --from=infisical /bin/infisical /usr/local/bin/infisical

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]