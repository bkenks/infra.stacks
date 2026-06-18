# Set env vars here
export DOCKER_ENVIRONMENT=test
export POSTGRES_USER=test
export POSTGRES_PASS=test
export ROOT_DOMAIN=test

# Compose Config - append any compose flags as arguments to this script
echo "\n---\n\nRendering Compose | Args: none | CMD: docker compose config\n\n---\n"
docker compose -f compose.yaml -f compose.production.yaml config