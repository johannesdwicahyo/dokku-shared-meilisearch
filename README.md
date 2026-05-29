# dokku-shared-meilisearch

[![CI](https://github.com/johannesdwicahyo/dokku-shared-meilisearch/actions/workflows/ci.yml/badge.svg)](https://github.com/johannesdwicahyo/dokku-shared-meilisearch/actions/workflows/ci.yml)

A [Dokku](https://dokku.com) plugin that runs **one shared Meilisearch container per host** and provisions tenants on it. Per-tenant isolation is enforced by **scoped Meilisearch API keys** restricted to indexes matching a `<tenant>-` prefix. A per-tenant size quota is enforced by a periodic sweep.

Companion to [dokku-shared-postgres](https://github.com/johannesdwicahyo/dokku-shared-postgres) and [dokku-shared-redis](https://github.com/johannesdwicahyo/dokku-shared-redis). Powers [wokku.cloud](https://wokku.cloud)'s shared Meilisearch tier.

## Install

```bash
dokku plugin:install https://github.com/johannesdwicahyo/dokku-shared-meilisearch.git
```

The install hook pulls the Meilisearch image, starts the shared container with a generated master key, sets up `/etc/cron.d/dokku-shared-meilisearch` for the quota sweep, and chowns the plugin data dir to `dokku:dokku`.

## Quick start

```bash
# Provision a tenant. Prints MEILISEARCH_URL + MEILISEARCH_API_KEY.
dokku shared-meilisearch:create my-search

# Wire it into an app (sets both env vars).
dokku shared-meilisearch:link my-search my-app

# Inspect.
dokku shared-meilisearch:info my-search
dokku shared-meilisearch:list

# Cap usage. Default is 100 MB per tenant.
dokku shared-meilisearch:set-quota my-search 250

# Tear down.
dokku shared-meilisearch:unlink my-search my-app
dokku shared-meilisearch:destroy my-search -f
```

## The prefix gotcha

The tenant's API key is scoped to `indexes: ["<name>-*"]` — **every index your app creates MUST be named `<name>-...`** (e.g. `my-search-products`). Requests against any other index name fail with a `403`. This is the trade for not paying the cost of one container per tenant.

In the Meilisearch clients, prefix your index names:

```ruby
# Ruby — gem 'meilisearch'
client = MeiliSearch::Client.new(ENV.fetch("MEILISEARCH_URL"), ENV.fetch("MEILISEARCH_API_KEY"))
index  = client.index("my-search-products")   # note the "my-search-" prefix
index.add_documents([{ id: 1, title: "Hello" }])
```

```js
// Node — meilisearch-js
import { MeiliSearch } from 'meilisearch'
const client = new MeiliSearch({ host: process.env.MEILISEARCH_URL, apiKey: process.env.MEILISEARCH_API_KEY })
await client.index('my-search-products').addDocuments([{ id: 1, title: 'Hello' }])
```

```python
# Python — meilisearch
import os, meilisearch
client = meilisearch.Client(os.environ["MEILISEARCH_URL"], os.environ["MEILISEARCH_API_KEY"])
client.index("my-search-products").add_documents([{"id": 1, "title": "Hello"}])
```

## How tenancy works

- **One container per host.** Started with a generated `MEILI_MASTER_KEY` and `MEILI_ENV=production`. The master key lives in `/var/lib/dokku/services/shared-meilisearch/.master_key` (mode 0600) and is never exposed to tenants.
- **Two API keys per tenant**, both scoped to `<name>-*`: a full-CRUD key (used by linked apps) and a read-only key (used during quota enforcement). Both are stable for the tenant's lifetime.
- **`link`** sets `MEILISEARCH_URL=http://dokku-shared-meilisearch:7700` and `MEILISEARCH_API_KEY=<full key>` on the app.

## Quotas

One size cap per tenant (MB). Default: **100 MB**. The cron job runs `dokku shared-meilisearch:check-quotas` every 5 minutes, summing each tenant's `<name>-*` index sizes.

**When a tenant exceeds its cap, its linked apps are switched to the read-only key and restarted** — search keeps working, writes return `403`. When usage drops comfortably below the cap (under 90%, a hysteresis margin to avoid flap-restarts), the full key is restored and the apps restart again.

> **Note:** Unlike the Redis plugin (which flips permissions on a live credential), Meilisearch API keys are immutable, so enforcement swaps *which key the app holds* — which requires an app restart. This only happens on a cap crossing, not on every sweep.

```bash
dokku shared-meilisearch:check-quotas   # run the sweep on demand
```

Output is one `flipped` / `released` line per state change; otherwise silent.

## Commands

```text
shared-meilisearch:create <name>            Create a tenant (two scoped keys + <name>-* prefix).
shared-meilisearch:destroy <name> -f        Delete the tenant's keys + all <name>-* indexes.
shared-meilisearch:link <name> <app>        Set MEILISEARCH_URL + MEILISEARCH_API_KEY on <app>.
shared-meilisearch:unlink <name> <app>      Remove those env vars from <app>.
shared-meilisearch:list                     All tenants on this host.
shared-meilisearch:info <name>              Indexes, size, quota, links, read-only state.
shared-meilisearch:connect <name>           Shell in the container with the tenant key preset.
shared-meilisearch:set-quota <name> <mb>    Set the per-tenant size cap.
shared-meilisearch:unset-quota <name>       Revert to the default cap.
shared-meilisearch:check-quotas             Run the quota sweep manually.
shared-meilisearch:export <name>            [stretch goal — not in v0.1.0]
shared-meilisearch:import <name>            [stretch goal — not in v0.1.0]
shared-meilisearch:help                     Show usage.
```

## When NOT to use this

- You need cross-host replication or Meilisearch Pro/Enterprise HA. Out of scope.
- You need more than a few hundred MB per tenant. Provision a dedicated Meilisearch instead.
- You need custom analyzers/tokenizers or vector search tuned per tenant. Host-wide defaults only here.

## Development

```bash
make lint   # shellcheck -x
make test   # bats tests
```

Integration smoke (run on a real Dokku host):

```bash
ssh root@my-dokku-host 'bash -s' < tests/integration_smoke.sh
```

## License

MIT — see `LICENSE`.
