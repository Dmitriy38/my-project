FROM golang:alpine AS builder
WORKDIR /src
COPY go.mod .
COPY go.sum .
RUN go mod download
COPY main.go .
RUN go build

FROM alpine:3.15
WORKDIR /app
COPY --from=builder /src/hello-docker /app/hello-docker
ENTRYPOINT ["/app/hello-docker"]

