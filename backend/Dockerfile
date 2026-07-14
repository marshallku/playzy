# Playzy backend image. Pure-Go build (modernc.org/sqlite, no cgo) so the binary
# is fully static and ships on distroless. The prompts/*.md are compiled in via
# go:embed (prompt.go), so nothing extra needs copying at runtime.
#
# Build context is this directory (backend/), where go.mod lives:
#   docker build -t playzy-backend backend/
FROM golang:1.25-alpine AS builder

WORKDIR /build

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /playzy-backend .

FROM gcr.io/distroless/static-debian12

COPY --from=builder /playzy-backend /playzy-backend

EXPOSE 8080

ENTRYPOINT ["/playzy-backend"]
