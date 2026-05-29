# dokku-shared-meilisearch

Shared, multi-tenant Meilisearch plugin for Dokku. One Meilisearch
container per host; per-tenant isolation via **scoped API keys** that
grant access only to indexes matching the tenant's prefix. Plugin-level
size-cap quota enforcement via cron.

**Status:** scaffolded 2026-05-30. v0.1.0 not yet built. See `CLAUDE.md`
for the complete onboarding brief.

## Why Meilisearch (not Elasticsearch)

10× smaller image, 20× less RAM, native multi-tenancy via scoped API
keys, MIT-licensed multi-tenancy primitives (not stuck behind Elastic's
X-Pack license).

## Why

Companion to:

- [dokku-shared-postgres](https://github.com/johannesdwicahyo/dokku-shared-postgres)
- [dokku-shared-redis](https://github.com/johannesdwicahyo/dokku-shared-redis)
- [dokku-shared-minio](https://github.com/johannesdwicahyo/dokku-shared-minio)
- [dokku-shared-memcached](https://github.com/johannesdwicahyo/dokku-shared-memcached)
- [dokku-shared-rabbitmq](https://github.com/johannesdwicahyo/dokku-shared-rabbitmq)

Backs the every-box-includes-Meilisearch tier in
[Wokku Cloud](https://wokku.cloud) plans (bundle v2).

## License

MIT (target).
