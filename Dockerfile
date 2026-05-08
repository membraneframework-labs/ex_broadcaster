# syntax=docker/dockerfile:1.7

ARG ELIXIR_VERSION=1.17.3
ARG OTP_VERSION=27.1.2
ARG UBUNTU_VERSION=jammy-20240808

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-ubuntu-${UBUNTU_VERSION} AS builder

ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      cmake \
      pkg-config \
      git \
      ca-certificates \
      nasm \
      yasm \
      glslang-tools \
      libvulkan-dev \
      libavcodec-dev \
      libavformat-dev \
      libavutil-dev \
      libswscale-dev \
      libswresample-dev \
      libavfilter-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod && mix deps.compile

COPY lib lib

RUN mix compile && mix release


FROM nvcr.io/nvidia/cuda:12.4.1-runtime-ubuntu22.04 AS runtime

ENV LANG=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive \
    NVIDIA_DRIVER_CAPABILITIES=video,compute,utility,graphics \
    NVIDIA_VISIBLE_DEVICES=all

RUN apt-get update && apt-get install -y --no-install-recommends \
      libstdc++6 \
      libssl3 \
      libncurses6 \
      libsctp1 \
      ca-certificates \
      locales \
      libvulkan1 \
      vulkan-tools \
      libavcodec58 \
      libavformat58 \
      libavutil56 \
      libswscale5 \
      libswresample3 \
      libavfilter7 \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen en_US.UTF-8

RUN groupadd --system app && useradd --system --gid app --create-home --home /app app

WORKDIR /app

COPY --from=builder --chown=app:app /app/_build/prod/rel/ex_broadcaster ./

USER app

EXPOSE 1935 8080

ENTRYPOINT ["/app/bin/ex_broadcaster"]
CMD ["start"]
