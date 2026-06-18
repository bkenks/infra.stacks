# Set env vars here
export POSTGRES_USER=test
export POSTGRES_PASS=test
export PG_ADMIN_PASS=test

# Compose Config - append any compose flags as arguments to this script
echo "\n---\n\nRendering Compose | Args: none | CMD: docker compose config\n\n---\n"
docker compose config


echo "\n---\n\nRendering Compose | Args: --profile full | CMD: docker compose config\n\n---\n"
docker compose --profile full config



echo "\n---\n\nRendering Compose | Args: --profile no_pgadmin | CMD: docker compose config\n\n---\n"
docker compose --profile no_pgadmin config