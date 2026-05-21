FROM golang:1.25-alpine AS builder

WORKDIR /src

COPY go.mod ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o /out/sample-app ./cmd/sample-app

FROM alpine:3.22

WORKDIR /app

COPY --from=builder /out/sample-app ./sample-app

EXPOSE 8080

ENTRYPOINT ["./sample-app"]