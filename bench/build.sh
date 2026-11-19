#!/bin/sh
set -eu

# Each marker carries the wall-clock time in epoch milliseconds, so a parser does not depend on the time at which
# the provider received the log line. BusyBox `date` (Alpine) has no %N, so it falls back to Node, then to seconds.
mark() {
  now="$(date +%s%3N 2>/dev/null || true)"
  case "$now" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;;
    *) now="$(node -e 'process.stdout.write(String(Date.now()))' 2>/dev/null || printf '%s000' "$(date +%s)")" ;;
  esac
  printf '::bench::%s %s\n' "$1" "$now"
}

# The commit SHA is embedded at build time, so /version reports what was built, not a runtime setting.
# BENCH_COMMIT is the harness override (Fly passes it as a build arg); the others are provider variables.
commit_sha() {
  for sha in "${BENCH_COMMIT:-}" "${RENDER_GIT_COMMIT:-}" "${RAILWAY_GIT_COMMIT_SHA:-}" "${VERCEL_GIT_COMMIT_SHA:-}"; do
    if [ -n "$sha" ]; then
      printf '%s\n' "$sha"
      return
    fi
  done
  git rev-parse HEAD 2>/dev/null || printf '%s\n' unknown
}

# Install: the web UI's npm packages and the Go modules. Upstream CI installs the UI with bun; the Makefile falls
# back to npm, and package-lock.json is in the repo, so npm ci gives a reproducible install without bun.
install() {
  mark install_start
  node --version
  go version
  (cd internal/site && npm ci --no-audit --no-fund)
  go mod download
  mark install_done
}

# Build: the web UI (lingui + tsc + vite, as upstream's `build` script), then the hub binary, which embeds the UI.
# The flags are upstream's (`make build-hub`); the -X flag sets the commit for /version.
build() {
  mark build_start
  (cd internal/site && npm run build)
  CGO_ENABLED=0 go build -ldflags "-w -s -X github.com/henrygd/beszel/internal/hub.benchCommit=$(commit_sha)" \
    -o beszel ./internal/cmd/hub
  mark build_done
}

case "${1:-all}" in
  install) install ;;
  build) build ;;
  all) install; build ;;
  *) printf 'Usage: %s {install|build|all}\n' "$0" >&2; exit 2 ;;
esac
