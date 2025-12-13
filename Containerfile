FROM docker.io/library/alpine:latest AS build

RUN exit 1

FROM scratch AS ctx
COPY /system_files/shared /system_files/shared/
COPY --from=build /out/homebrew.tar.zstd /system_files/usr/share/homebrew.tar.zstd
