#!/usr/bin/env bash
# Railway wrapper for MemMachine: writes configuration.yml from service variables,
# waits for PostgreSQL and Qdrant, then runs MemMachine on loopback behind Caddy.
set -euo pipefail

log() { echo "[railway-start] $*" >&2; }

# --- required settings ---------------------------------------------------------
MEMMACHINE_API_KEY="${MEMMACHINE_API_KEY:-}"
if [ "${#MEMMACHINE_API_KEY}" -lt 16 ]; then
  log "MEMMACHINE_API_KEY is empty or shorter than 16 characters. The template generates one; set it on the service."
  exit 1
fi
for v in POSTGRES_HOST POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB QDRANT_HOST; do
  if [ -z "${!v:-}" ]; then log "$v is empty. It should reference the Postgres or Qdrant service."; exit 1; fi
done
if [ -z "${OPENAI_API_KEY:-}" ]; then
  log "OPENAI_API_KEY is empty. MemMachine checks the embedding model and the LLM at startup and stops without a working key."
  log "Set OPENAI_API_KEY (and OPENAI_BASE_URL for another OpenAI-compatible provider) on this service, then redeploy."
  exit 1
fi

# --- defaults (each one can be overridden with a service variable) --------------
export PORT="${PORT:-8080}"
export POSTGRES_PORT="${POSTGRES_PORT:-5432}"
export QDRANT_PORT="${QDRANT_PORT:-6333}"
export OPENAI_BASE_URL="${OPENAI_BASE_URL:-https://api.openai.com/v1}"
export LLM_MODEL="${LLM_MODEL:-gpt-4o-mini}"
export EMBEDDING_MODEL="${EMBEDDING_MODEL:-text-embedding-3-small}"
export EMBEDDING_DIMENSIONS="${EMBEDDING_DIMENSIONS:-1536}"
# OpenAI itself gets the Responses API; any other OpenAI-compatible endpoint gets Chat Completions.
if [ -z "${LLM_API:-}" ]; then
  case "$OPENAI_BASE_URL" in
    https://api.openai.com/*) LLM_API=openai-responses ;;
    *) LLM_API=openai-chat-completions ;;
  esac
fi
export LLM_API
export MEMMACHINE_INTERNAL_PORT="${MEMMACHINE_INTERNAL_PORT:-8081}"
export MEMORY_CONFIG="${MEMORY_CONFIG:-/app/configuration.yml}"

# --- configuration.yml (JSON is valid YAML; secrets stay as $ENV references) ----
python - <<'PY'
import json, os
e = os.environ
cfg = {
  "logging": {"path": "/tmp/memmachine.log", "level": e.get("LOG_LEVEL", "info").lower()},
  "episode_store": {"database": "profile_storage"},
  "episodic_memory": {
    "long_term_memory": {
      "backend": "event",
      "embedder": "llm_embedder",
      "reranker": "my_reranker_id",
      "vector_store": "event_vector_store",
      "segment_store": "profile_storage",
    },
    "short_term_memory": {"llm_model": "llm_model", "message_capacity": 500},
  },
  "retrieval_agent": {"llm_model": "llm_model", "reranker": "my_reranker_id"},
  "semantic_memory": {
    "llm_model": "llm_model",
    "embedding_model": "llm_embedder",
    "database": "profile_storage",
    "config_database": "profile_storage",
  },
  "session_manager": {"database": "profile_storage", "instance_cache_size": 0},
  "prompt": {"default_project_categories": ["profile_prompt"]},
  "resources": {
    "databases": {
      "profile_storage": {"provider": "postgres", "config": {
        "host": e["POSTGRES_HOST"], "port": int(e["POSTGRES_PORT"]),
        "user": e["POSTGRES_USER"], "password": "$POSTGRES_PASSWORD",
        "db_name": e["POSTGRES_DB"], "pool_size": 5, "max_overflow": 10,
      }},
      "event_vector_store": {"provider": "qdrant", "config": {
        "host": e["QDRANT_HOST"], "port": int(e["QDRANT_PORT"]),
        "prefer_grpc": False, "https": False, "api_key": "$QDRANT_API_KEY",
      }},
    },
    "embedders": {"llm_embedder": {"provider": "openai", "config": {
      "max_input_length": 2048, "model": e["EMBEDDING_MODEL"], "api_key": "$OPENAI_API_KEY",
      "base_url": e["OPENAI_BASE_URL"], "dimensions": int(e["EMBEDDING_DIMENSIONS"]),
    }}},
    "language_models": {"llm_model": {"provider": e["LLM_API"], "config": {
      "model": e["LLM_MODEL"], "api_key": "$OPENAI_API_KEY", "base_url": e["OPENAI_BASE_URL"],
    }}},
    "rerankers": {
      "my_reranker_id": {"provider": "rrf-hybrid", "config": {"reranker_ids": ["id_ranker_id", "bm_ranker_id"]}},
      "id_ranker_id": {"provider": "identity"},
      "bm_ranker_id": {"provider": "bm25"},
    },
  },
}
with open(e["MEMORY_CONFIG"], "w") as f:
    json.dump(cfg, f, indent=2)
PY
export OPENAI_API_KEY="${OPENAI_API_KEY:-}" QDRANT_API_KEY="${QDRANT_API_KEY:-}"

# --- wait for the databases (Railway starts all services at once) ---------------
wait_for() {  # host port name
  local i
  for i in $(seq 1 90); do
    if python -c "import socket,sys; socket.create_connection((sys.argv[1], int(sys.argv[2])), 3).close()" "$1" "$2" 2>/dev/null; then
      log "$3 is reachable at $1:$2"; return 0
    fi
    sleep 2
  done
  log "$3 at $1:$2 is still unreachable after 3 minutes"; exit 1
}
wait_for "$POSTGRES_HOST" "$POSTGRES_PORT" PostgreSQL
wait_for "$QDRANT_HOST" "$QDRANT_PORT" Qdrant

# --- run MemMachine on loopback and Caddy on $PORT; stop when either exits ------
log "starting MemMachine (LLM $LLM_MODEL via $LLM_API, embeddings $EMBEDDING_MODEL at $OPENAI_BASE_URL)"
log "if it stops with an AuthenticationError, check OPENAI_API_KEY and OPENAI_BASE_URL"
HOST=127.0.0.1 PORT="$MEMMACHINE_INTERNAL_PORT" memmachine-server &
mm=$!
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
cd_pid=$!
trap 'kill -TERM $mm $cd_pid 2>/dev/null' TERM INT
set +e
wait -n $mm $cd_pid
code=$?
log "a process exited (code $code); stopping the container"
kill -TERM $mm $cd_pid 2>/dev/null
wait
exit "$code"
