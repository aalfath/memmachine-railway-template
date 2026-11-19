[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/memmachine?utm_medium=integration&utm_source=button&utm_campaign=memmachine)

# MemMachine on Railway

One-click [MemMachine](https://github.com/MemMachine/MemMachine) for Railway: an open-source memory layer for AI agents. It stores conversation episodes and user profile facts and returns the relevant ones through a REST API, an MCP server and the Python and TypeScript clients.

**Version:** MemMachine `v0.4.0`, official CPU image `memmachine/memmachine:v0.4.0-cpu@sha256:80535e8ad4cd60024740e4b58fa723fcbea49e5a5a7ddb072d0e7518def038a9`.

## What the template deploys

| Service | Source | What it does | Volume |
|---|---|---|---|
| **MemMachine** | `memmachine/` in this repo | The MemMachine server (REST API at `/api/v2`, MCP at `/mcp`) behind Caddy `2.11.9`, which checks an API key on every request. Public domain on port 8080, health check `/api/v2/health`. | none (stateless) |
| **Qdrant** | `qdrant/` in this repo, `qdrant/qdrant:v1.20.2@sha256:d277592721d2e3b73f9b797b53cf05e6a5bb2134f6d13fdbda4ca51782afbcac` | Vector store for long-term episodic memory (MemMachine's default `event` backend). Private only, protected by a generated API key. Health check `/readyz`. | `/qdrant/data` |
| **Postgres** | Railway's Postgres (has pgvector) | Episodes, sessions, projects, semantic (profile) memory and the episode segments. MemMachine runs its migrations on boot. | `/var/lib/postgresql/data` |

MemMachine waits for Postgres and Qdrant before it starts, so all three come up together on the first deploy.

## Variables

| Service | Variable | Default | Notes |
|---|---|---|---|
| MemMachine | `OPENAI_API_KEY` | *(you enter it)* | The only prompt. MemMachine checks the key at startup and stops without a working one. |
| MemMachine | `MEMMACHINE_API_KEY` | `${{secret(48,…)}}` | API key clients send as `Authorization: Bearer <key>`. Read it in the service's Variables tab. |
| MemMachine | `OPENAI_BASE_URL` | `https://api.openai.com/v1` | Any OpenAI-compatible endpoint (OpenRouter, Together, a vLLM or Ollama server you run). Non-OpenAI URLs use the Chat Completions API. |
| MemMachine | `LLM_MODEL` | `gpt-4o-mini` | Model for summaries and profile extraction. |
| MemMachine | `EMBEDDING_MODEL` | `text-embedding-3-small` | Embedding model. Set `EMBEDDING_DIMENSIONS` (default 1536) if you pick a model with another size, before you store memories. |
| MemMachine | `POSTGRES_*`, `QDRANT_*` | references | Wired to the Postgres and Qdrant services over the private network. |
| MemMachine | `PORT` | `8080` | Public port (Caddy). MemMachine itself listens on `127.0.0.1:8081`. |
| Qdrant | `QDRANT__SERVICE__API_KEY` | `${{secret(48)}}` | Qdrant API key; MemMachine reads it by reference. |
| Qdrant | `PORT` | `6333` | Qdrant REST port. |

Optional: `LOG_LEVEL` (`info`), `MEMMACHINE_WORKERS` (`1`), `LLM_API` (`openai-responses` or `openai-chat-completions`, picked from the URL by default).

## After deploy

```sh
export MM_URL=https://YOUR-DOMAIN.up.railway.app
export MM_KEY=...   # MEMMACHINE_API_KEY from the MemMachine service's Variables tab

curl -X POST $MM_URL/api/v2/memories -H "Authorization: Bearer $MM_KEY" -H "content-type: application/json" \
  -d '{"org_id":"acme","project_id":"demo","messages":[{"content":"I live in Lisbon","producer":"alice","role":"user"}]}'
curl -X POST $MM_URL/api/v2/memories/search -H "Authorization: Bearer $MM_KEY" -H "content-type: application/json" \
  -d '{"org_id":"acme","project_id":"demo","query":"Where does Alice live?"}'
```

Python: `MemMachineClient(api_key=MM_KEY, base_url=MM_URL)`. MCP clients connect to `$MM_URL/mcp/` with the same `Authorization` header. The API description at `/docs` is public; everything else needs the key.

## Not included

- **Neo4j:** upstream runs Neo4j only for the alternative `declarative` long-term memory backend. The default `event` backend uses Qdrant plus Postgres, so this template ships those.
- **The docs site** from upstream's compose file (a local copy of docs.memmachine.ai).

## Updates

All app services build from this repo's `main` branch. When we bump MemMachine or Qdrant here, Railway shows deployers an "update available" notice, and you choose when to apply it. Read [CHANGELOG.md](CHANGELOG.md) first; breaking changes are listed at the top of each entry. MemMachine migrates its Postgres schema on boot.
