# syntax=docker/dockerfile:1.7

ARG ELIXIR_VERSION=1.17.3
ARG OTP_VERSION=27.1.2

# Builder stage - use CUDA base image
FROM nvcr.io/nvidia/cuda:12.4.1-base-ubuntu22.04 AS builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV MIX_ENV=prod \
  LANG=C.UTF-8 \
  DEBIAN_FRONTEND=noninteractive \
  ERL_AFLAGS="+JMsingle true"

RUN apt-get update 
RUN apt-get install software-properties-common -y
RUN add-apt-repository ppa:rabbitmq/rabbitmq-erlang
RUN apt-get update 

# Install build dependencies
RUN apt-get install -y --no-install-recommends \
  build-essential \
  cmake \
  curl \
  pkg-config \
  libvulkan-dev \
  git \
  elixir \
  erlang \
  && rm -rf /var/lib/apt/lists/*

# Download and install Erlang and Elixir using direct .deb downloads

# Install Rust
ENV RUSTUP_HOME=/usr/local/rustup \
  CARGO_HOME=/usr/local/cargo \
  PATH=/usr/local/cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable \
  && rustc --version && cargo --version

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config
COPY --from=transcoder_plugin . /membrane_transcoder_plugin
RUN mix deps.get --only prod && mix deps.compile

COPY lib lib

ENV MIX_ENV=prod
RUN mix compile && mix release && cp -r _build/prod/rel/ex_broadcaster /app/release


# Runtime stage - use CUDA base image for GPU support with Vulkan
FROM nvcr.io/nvidia/cuda:12.4.1-base-ubuntu22.04 AS runtime

ENV LANG=C.UTF-8 \
  DEBIAN_FRONTEND=noninteractive \
  NVIDIA_DRIVER_CAPABILITIES=compute,graphics \
  NVIDIA_VISIBLE_DEVICES=all

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
  libstdc++6 \
  libssl3 \
  libncurses6 \
  libsctp1 \
  ca-certificates \
  libegl1-mesa-dev \
  libgl1-mesa-dri \
  libxcb-xfixes0-dev \
  mesa-vulkan-drivers \
  locales \
  gnupg \
  wget \
  && rm -rf /var/lib/apt/lists/* \
  && locale-gen en_US.UTF-8

RUN wget -qO - https://packages.lunarg.com/lunarg-signing-key-pub.asc | gpg --dearmor -o /usr/share/keyrings/lunarg-signing-key-pub.gpg \
  && echo "deb [signed-by=/usr/share/keyrings/lunarg-signing-key-pub.gpg] https://packages.lunarg.com/vulkan/ jammy main" \
  > /etc/apt/sources.list.d/lunarg-vulkan-jammy.list \
  && apt-get update && apt-get install -y --no-install-recommends libvulkan1 \
  && rm -rf /var/lib/apt/lists/*

RUN groupadd --system app && useradd --system --gid app --create-home --home /app app

WORKDIR /app

COPY --from=builder --chown=app:app /app/release ./

USER app

EXPOSE 1935 8080

ENTRYPOINT ["/app/bin/ex_broadcaster"]
CMD ["start"]
