# build-deploy-bench image of the Beszel hub. All four providers build this file: Render (runtime docker), Railway
# (Dockerfile builder), Fly (fly.toml [build]) and Vercel (vercel.json framework "container").
# Based on upstream internal/dockerfile_hub. Upstream CI builds the web UI outside Docker, so this file adds Node to
# the build stage. Base images are pinned by tag and digest. No BuildKit-only syntax (Vercel builds with Buildah) and
# no --platform (every provider builds linux/amd64 natively).

# The Go toolchain only; the build stage copies it.
FROM golang:1.27.4-alpine@sha256:0a5f7fe796599ff487605987432e7619ae45beeb2fba4c2ce0b907879932aebf AS go

# One build stage with Node and Go, so that the install and build steps are each one RUN with one pair of markers.
FROM node:24.22.3-alpine@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5 AS build
COPY --from=go /usr/local/go /usr/local/go
ENV PATH=/usr/local/go/bin:/root/go/bin:$PATH \
    GOTOOLCHAIN=local
WORKDIR /app

# Install: copy only the manifests, so a warm layer cache can skip this step when only sources change.
COPY go.mod go.sum ./
COPY internal/site/package.json internal/site/package-lock.json internal/site/
COPY bench/build.sh bench/build.sh
RUN sh ./bench/build.sh install

# The image has no .git, so the commit SHA for /version comes from a build arg. Render and Railway pass their
# variables as build args, Vercel passes VERCEL_GIT_COMMIT_SHA (Git deploys only), and the harness passes
# BENCH_COMMIT to Fly. A RUN step sees a build arg only after its ARG line. The ARGs come after the install step,
# so a new commit does not invalidate the install layer.
ARG BENCH_COMMIT=""
ARG RENDER_GIT_COMMIT=""
ARG RAILWAY_GIT_COMMIT_SHA=""
ARG VERCEL_GIT_COMMIT_SHA=""
COPY . ./
RUN sh ./bench/build.sh build

# Runtime: the static binary and CA certificates on scratch, as upstream.
FROM scratch
COPY --from=build /app/beszel /
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
# The hub listens on $PORT (internal/hub/bench.go). 80 is Vercel's routed port; Render and Railway set their own.
ENV PORT=80
EXPOSE 80
ENTRYPOINT ["/beszel"]
CMD ["serve"]
