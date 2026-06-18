# Bifrost Source Build

This project uses `bifrost-src` as a git submodule for Bifrost source changes.
Do not copy an upstream Bifrost checkout into this repository.

## Source Pin

The project-owned fork is `https://github.com/dpolishuk/bifrost.git`.

`bifrost-src` is pinned to commit:

```text
84301b6ecfaac19c24c9b699cf6b55ad16af8756
```

Docker Hub maps the current digest-pinned image to the `v1.5.15` image tag:

```text
maximhq/bifrost@sha256:240634280b374bf0fae11e888f5f9238bf30a2c323a75d905059902fea2c7a5d
```

The upstream source tag `transports/v1.5.15` peels to
`84301b6ecfaac19c24c9b699cf6b55ad16af8756`. The OCI metadata exposed by
`docker buildx imagetools inspect` did not include a source revision label, so
the submodule pin is chosen as the source tag that corresponds to the Docker
image tag behind the digest.

## Initialize

For a fresh checkout:

```bash
git submodule update --init --recursive bifrost-src
git submodule status bifrost-src
```

If the fork ever needs to be recreated:

```bash
gh repo fork maximhq/bifrost --clone=false
```

Then update `.gitmodules` to point at the accessible project-owned fork and pin
`bifrost-src` to a reviewed commit.

## Build And Run

The `bifrost` service builds from the submodule:

```yaml
build:
  context: ./bifrost-src
  dockerfile: transports/Dockerfile
```

Build or start Bifrost through Compose:

```bash
docker compose build bifrost
docker compose up -d bifrost
```

Bifrost remains internal to the Compose network:

- no host `ports` on the `bifrost` service
- `expose: ["8081"]`
- `bifrost_data:/app/data` remains the data volume
- PromptShield Gateway continues to forward allowed inference traffic to
  `http://bifrost:8081/v1`

PromptShield settings in the Bifrost container are server-only environment
variables for future Bifrost proxy handlers. Commit only variable references and
safe internal defaults, never real values:

- `PROMPTSHIELD_DASHBOARD_URL`
- `PROMPTSHIELD_GATEWAY_URL`
- `PROMPTSHIELD_ENGINE_URL`
- `PROMPTSHIELD_ADMIN_TOKEN`
- `PROMPTSHIELD_GATEWAY_ADMIN_TOKEN`
- `PROMPTSHIELD_ENGINE_API_KEY`

Provider routing, provider keys, model routes, fallback order, provider
secrets, and key pools remain Bifrost-owned configuration.

## Rollback

To roll back to the previous digest-pinned upstream image:

1. Stop Bifrost: `docker compose stop bifrost`.
2. In `docker-compose.yml`, remove the `bifrost.build` block and restore:

   ```yaml
   image: maximhq/bifrost@sha256:240634280b374bf0fae11e888f5f9238bf30a2c323a75d905059902fea2c7a5d
   ```

3. Leave the PromptShield-specific Bifrost environment variables unused or
   remove them.
4. Start Bifrost: `docker compose up -d bifrost`.
5. Confirm `/bifrost/` still loads and public `/v1/*` traffic still flows
   through PromptShield Gateway before Bifrost.

The rollback does not change PromptShield dashboard, gateway, engine, Postgres,
policy files, or the `bifrost_data` volume.
