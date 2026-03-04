FROM golang:1.21-alpine AS builder

WORKDIR /app
COPY go.mod ./
COPY *.go ./

RUN go build -o iblups-ingest .

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/iblups-ingest /app/iblups-ingest

EXPOSE 3000

CMD ["/app/iblups-ingest"]
