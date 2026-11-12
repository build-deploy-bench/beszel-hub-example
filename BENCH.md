# Build-deploy benchmark fixture: docker-small (Beszel hub)

## Source

- Upstream: https://github.com/henrygd/beszel at tag `v0.21.1` = `e2ed147a5aa6472e6462521632ccc7101668132c`. MIT license, kept in `LICENSE`. The hub is Go (PocketBase with embedded SQLite) and embeds a React UI built with Vite.
- This repo: https://github.com/build-deploy-bench/beszel-hub-example (private, independent copy). The first commit is the unmodified upstream at the pinned commit; our patches are the later commits.
- Tier: docker-small (<50 MB image). Measured on the fixture image built from `ea24f2e` (linux/amd64): **13.5 MB compressed** (sum of the gzip layers), **34.1 MB uncompressed** (layer tars; the binary is 33.9 MB). The published upstream image is 13 MB / 34 MB.

## Patches

1. `internal/hub/bench.go` (new) plus one line each in `internal/hub/hub.go` and `internal/cmd/hub/hub.go`:
   - `GET /version` returns `{"commit":"<sha>","run":"<id>","deployment":"<id>"}`, registered in an `OnServe` hook. `commit` is set at build time with `-ldflags -X github.com/henrygd/beszel/internal/hub.benchCommit=<sha>`. `run` is the runtime env var `BENCH_RUN_ID` and `deployment` is `RAILWAY_DEPLOYMENT_ID` (else `unknown`), as in the other fixtures.
   - `::bench::start` is printed first in `main`. `::bench::listening` is printed by an `OnServe` handler after `e.Next()` returns: PocketBase binds the listen socket in the last handler of that chain, so the socket is bound at that point.
   - Listen address: when `PORT` is set and `serve` has no `--http` flag, the hub adds `--http=0.0.0.0:$PORT`. Upstream's image passes `--http=0.0.0.0:8090` in `CMD`; the scratch image has no shell to expand `$PORT` there. Without `PORT`, upstream behavior is unchanged.
2. `internal/hub/bench_touch.go`: the touch file for warm runs (an unused constant).
3. Upstream GitHub Actions workflows removed (one is scheduled).
4. Added `bench/build.sh`, a root `Dockerfile`, `fly.toml` and `vercel.json`. Upstream's `internal/dockerfile_hub` is unchanged and unused.

The hub needs no env vars and no external database. PocketBase creates `/beszel_data` in the container at the first start, so data is lost on each deploy.

## Commands

| Step | Command | Markers |
|---|---|---|
| Install | `./bench/build.sh install` = `node --version && go version && (cd internal/site && npm ci --no-audit --no-fund) && go mod download` | `::bench::install_start` / `::bench::install_done` |
| Build | `./bench/build.sh build` = `(cd internal/site && npm run build) && CGO_ENABLED=0 go build -ldflags "-w -s -X …benchCommit=<sha>" -o beszel ./internal/cmd/hub` | `::bench::build_start` / `::bench::build_done` |
| Start | `/beszel serve` (image `ENTRYPOINT` + `CMD`) | `::bench::start` / `::bench::listening` |
| Health | `GET /api/health` returns 200 | |

`npm run build` is upstream's script: `lingui extract --overwrite && lingui compile && tsc -b && vite build`. Upstream CI installs and builds the UI with bun outside Docker; the fixture uses npm, which upstream's Makefile also supports, because `package-lock.json` is in the repo and the build then needs only the Node image. `--no-audit --no-fund` skips two network calls that do not change the install. The build runs `npm run build` and `go build` in one step because the Go binary embeds `internal/site/dist`.

`bench/build.sh` marks with `date +%s%3N`. BusyBox `date` (Alpine) has no `%N` and prints 10 digits, which the marker pattern rejects, so the script falls back to `node -e Date.now()`. The commit SHA is the first value in `BENCH_COMMIT`, `RENDER_GIT_COMMIT`, `RAILWAY_GIT_COMMIT_SHA` or `VERCEL_GIT_COMMIT_SHA`, then `git rev-parse HEAD`, then `unknown`.

## Dockerfile

All four providers build the root `Dockerfile`. It is upstream's `internal/dockerfile_hub` with these changes:

- A Node build stage: upstream CI builds the UI before `docker build`. The build stage is `node:24.22.3-alpine` with the Go toolchain copied from `golang:1.27.4-alpine`, so the install and build steps are each one `RUN` with one marker pair. Both base images are pinned by tag and digest (upstream: unpinned `golang:alpine`). Go 1.27.4 is the newest patch of the `go 1.27.2` line in `go.mod`.
- No `FROM --platform=$BUILDPLATFORM` and no `TARGETOS`/`TARGETARCH` cross-compile: every provider builds `linux/amd64` natively, and Vercel builds with Buildah.
- No `apk add unzip ca-certificates`: the Alpine base already has `/etc/ssl/certs/ca-certificates.crt`, and the hub build does not use unzip. This keeps unpinned packages out of the build.
- The install inputs (`go.mod`, `go.sum`, `internal/site/package*.json`, `bench/build.sh`) are copied before the install step, so a warm build can skip it. Upstream's `.dockerignore` is unchanged.
- `ARG BENCH_COMMIT`, `RENDER_GIT_COMMIT`, `RAILWAY_GIT_COMMIT_SHA`, `VERCEL_GIT_COMMIT_SHA` after the install step. Render and Railway pass their variables as build args, but a `RUN` step sees one only after its `ARG` line. Before `ea24f2e`, `/version` returned `commit: unknown` on Render and Railway.
- Runtime: `scratch` with the binary and CA certificates, as upstream. `ENV PORT=80` (Vercel's routed port), `ENTRYPOINT ["/beszel"]`, `CMD ["serve"]`. Upstream's `VOLUME ["/beszel_data"]` is removed; no provider here mounts a volume.

## Providers

Plans: the same as the language fixtures. Render `starter` instance and `starter` build pipeline, Fly `shared-cpu-1x` with 1 GB (the `fly launch` default), Railway and Vercel on their paid plans.

### Render

- Service `srv-dbqu90jrjlhs73cea73g` `bdb-beszel-hub`, https://bdb-beszel-hub.onrender.com. Workspace `tea-dbmbhbg8v5cc73e4m0jg`, region `virginia`, runtime `docker` (`dockerfilePath: ./Dockerfile`, `dockerContext: .`), plan `starter`, build plan `starter`, health check `/api/health`, auto-deploy `off`. Created with `POST /v1/services` on 2026-11-12.
- Render sets `PORT=10000`, and the hub listens there (`==> Detected service running on port 10000`).
- Setup deploy `dep-dbqu913rjlhs73cea8cg` of `8824c22` is live. After the BuildKit build, Render pushes the image (`#<n> exporting to image` … `pushing layers`) and then runs `exporting cache to registry` (37 s on a cold build) before `==> Deploying...`. A Docker service prints no `==> Uploading build` or `==> Running '<command>'` line.

### Railway

- Project `bdb-beszel-hub` `acd45dc0-e414-4a96-9ecf-9a549525a19e`, environment `production` `75b2d8b9-2fb6-4a13-9860-bcf7abd8eeaf`, service `bdb-beszel-hub` `a659e49b-6283-40ba-8627-241eedd7d7c8`, https://bdb-beszel-hub-production.up.railway.app. Source `build-deploy-bench/beszel-hub-example` branch `main`.
- Builder: the service setting says `RAILPACK`, but Railway uses the Dockerfile builder when a root `Dockerfile` exists; the build log shows `load build definition from Dockerfile`. Health check `/api/health`. No variables. One replica, default region. Auto-deploy disabled with `serviceInstanceAutoDeployUpdate` and confirmed with `serviceInstanceAutoDeployStatus`.
- Setup deploy `7a3870f4-f471-4672-8f44-a2074d92fb45` of `8824c22` succeeded.

### Vercel

- Team `build-deploy-bench`, project `bdb-beszel-hub` `prj_0BETuk4fmyFRWab05untEI16vPlH`, https://bdb-beszel-hub.vercel.app. No Git link; deploys upload a `git archive` of the commit with `vercel deploy --prod`.
- Container Runtime through `vercel.json` `"framework": "container"`, which builds the root `Dockerfile` (no `Dockerfile.vercel`). Function region `iad1`. Build machine `standard`, selection `fixed`, the same as the other projects.
- Setup deploy `dpl_Hm8PxCQFA1GZjbHuC4VCsbHvUxNk` of `8824c22`: health 200 and `/version` returns `run`. `commit` is `unknown`, as for every CLI upload. The build log shows `[1/3] STEP …` for the three stages; the root file system of the scratch image is writable, so PocketBase starts.

### Fly.io

- Org `personal`, app `bdb-beszel-hub`, https://bdb-beszel-hub.fly.dev. One Machine (`80ee717f690048` after the bluegreen deploys; stopped), `iad`, `shared-cpu-1x` with 1 GB (the `fly launch` default), always on, `internal_port = 80`, health check `/api/health`.
- Deploy: `flyctl deploy --config fly.toml -a bdb-beszel-hub --remote-only --depot=false --ha=false --yes --strategy bluegreen --build-arg BENCH_COMMIT=<sha> --env BENCH_RUN_ID=<id>` from a `git archive` of the commit, as the harness does. The setup deploy of `8824c22` returned the right SHA.

## Check runs (2026-11-12)

One cold and one warm run per provider with `matrix/run.py`, in `../build-deploy-bench-runs/2026-11-12-docker-small-check/`. They check the setup and the parsers; they are not benchmark results. Every run that finished has all partition spans.

| Provider | Run | Cache seen | install | build | e2e (s) | Note |
|---|---|---|---:|---:|---:|---|
| Render | cold | cold | 8.6 | 69.7 | 153.4 | `release` 36.9 s, of which `cache_export` 35.4 s |
| Render | warm | warm | cached | 71.5 | 118.1 | `cache_export` 14.3 s |
| Railway | cold | cold | 11.3 | 55.6 | 98.6 | |
| Railway | warm | cold | 9.7 | 45.9 | 95.1 | No layer hit, as on the language fixtures |
| Vercel | cold | cold | 18.1 | 86.7 | 183.4 | |
| Vercel | warm | warm | cached | 75.8 | 124.8 | |
| Fly | cold | cold | 43.1 | 417.0 | 594.3 | Under the Fly lock; see below |
| Fly | warm | warm | cached | 354.7 | 397.1 | Under the Fly lock; see below |

The Fly runs held the shared Fly builder lock, and no other Fly build ran at the same time. Their build steps still took 6 to 7 minutes, against 46 to 87 s on the other providers and about 50 s on the idle setup deploy at 16:10. The builder `fly-builder-rosy-headland-8386` is a `shared` 8-CPU Machine (8 GB), and before the lock it ran the builds of six fixture threads for about an hour. The likely cause is that Fly throttled its shared CPUs to their baseline after the burst balance was used up; this is not confirmed. Repeat the Fly runs after the builder has been idle, or on a `performance` builder, before comparing Fly build times. The earlier Fly runs, which shared the builder with other threads, are in `invalid-fly-shared-builder/`.

The Fly setup deploy, on an idle builder, built in about 2 minutes and served the right commit. A touch commit changes only the Go build input, but the build step also runs `npm run build` again, because both are in one `RUN`.
