#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# PRE-FLIGHT
# ============================================================
# notes: Setup for environment, compose command, etc

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# COMPOSE BASE COMMAND SETUP
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Add flags that run everytime — each as its own element
# COMPOSE_BASE_COMMAND+=(-f compose.yaml)
# COMPOSE_BASE_COMMAND+=(-f compose.override.yaml)
# COMPOSE_BASE_COMMAND+=(--project-name myproject)
#
# A value with spaces stays ONE element — no quoting/splitting trouble
# COMPOSE_BASE_COMMAND+=(--project-directory "/path/with spaces")
COMPOSE_BASE_COMMAND=(docker compose)

# COMPOSE BASE COMMAND SETUP
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# ENVIRONMENT SETUP
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# notes: Set your environment variables here required to render the compose

export OPEN_PRJ_SECRET_KEY=test
export COLLAB_SERVER_SECRET=test
export POSTGRES_USER=test
export POSTGRES_PASS=test

# ENVIRONMENT SETUP
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# PRE-FLIGHT
# ============================================================

# ----- TEST 1 -----
# notes: Add addition flags or commands in each test
"${COMPOSE_BASE_COMMAND[@]}" config
