# docker buildx build --build-arg TARGETARCH=arm64 --platform linux/arm64 --file Dockerfile -t kafka-confluent-go-consumer:latest .

FROM --platform=linux/$TARGETARCH golang:1.21.4-alpine as builder

ARG TARGETARCH
RUN echo $TARGETARCH

# librdkafka package for alpine yet
# https://pkgs.alpinelinux.org/packages?name=librdkafka-dev&branch=edge&repo=&arch=&maintainer=John%20Anthony
RUN apk add musl-dev librdkafka-dev ca-certificates git gcc g++ libtool libc-dev pkgconf
RUN apk add build-base coreutils make musl-dev rpm wget curl cyrus-sasl-dev libevent libsasl lz4-dev openssh openssl openssl-dev yajl-dev zlib-dev

ENV LIBRD_VER=2.3.0
# Install librdkafka $LIBRD_VER
# https://gist.github.com/jaihind213/e82d41dc79f52cfa64ca32350bdb27df
#RUN apk --no-cache add ca-certificates git gcc g++ libtool libc-dev musl-dev pkgconf
#RUN apk add build-base coreutils make musl-dev rpm wget curl cyrus-sasl-dev libevent libsasl lz4-dev openssh openssl openssl-dev yajl-dev zlib-dev

#RUN echo " ------> Install librdkafka..."
#RUN apk add --no-cache --virtual .make-deps bash make wget git gcc g++
#RUN apk add --no-cache musl-dev zlib-dev openssl zstd-dev pkgconfig libc-dev
#RUN wget https://github.com/edenhill/librdkafka/archive/v${LIBRD_VER}.tar.gz && tar -xvf v${LIBRD_VER}.tar.gz && cd librdkafka-${LIBRD_VER} && ./configure --prefix /usr && make && make install && make clean && rm -rf librdkafka-${LIBRD_VER} && rm -rf v${LIBRD_VER}.tar.gz && apk del .make-deps

#RUN apk add --no-cache --virtual .make-deps bash make wget git gcc g++ && apk add --no-cache musl-dev zlib-dev openssl zstd-dev pkgconfig libc-dev
#RUN wget https://github.com/edenhill/librdkafka/archive/v${LIBRD_VER}.tar.gz
#RUN tar -xvf v${LIBRD_VER}.tar.gz && cd librdkafka-${LIBRD_VER} && ./configure --prefix /usr && make && make install
#RUN export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:/usr/lib/pkgconfig/
#ENV PKG_CONFIG_PATH=$PKG_CONFIG_PATH:/usr/lib/pkgconfig/

WORKDIR /app
COPY go.mod .
COPY go.sum .
RUN go mod download
COPY . .
RUN CGO_ENABLED=1 GOOS=linux GOARCH=$TARGETARCH go build -tags musl --ldflags "-extldflags -static" -a -o consumer consumer/consumer.go

FROM alpine:3.18.4 as runtime
COPY --from=builder /app/consumer /
EXPOSE 8080
CMD ["/bin/sh", "-c", "/consumer"]