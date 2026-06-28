# Set env vars here (the ${VAR:?err} secrets the app + db require)
export INFISICAL_ENCRYPTION_KEY=test
export INFISICAL_AUTH_SECRET=test
export INFISICAL_DB_PASSWORD=test

# Compose Config - append any compose flags as arguments to this script
echo "\n---\n\nRendering Compose | Args: none | CMD: docker compose config\n\n---\n"
docker compose config
