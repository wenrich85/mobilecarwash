# Stage 1: Build
FROM hexpm/elixir:1.17.3-erlang-27.1-debian-bookworm-20240904-slim AS builder

# Install build tools (needed for picosat_elixir and other native deps)
RUN apt-get update -y && apt-get install -y \
  build-essential \
  git \
  curl \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

# Set build env
ENV MIX_ENV=prod

# Install hex + rebar
RUN mix local.hex --force && mix local.rebar --force

# Install dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

# Compile dependencies
RUN mix deps.compile

# Copy config + source and compile Elixir first.
# This generates _build/prod/phoenix-colocated/ which esbuild needs.
COPY config config
COPY lib lib
COPY priv priv
RUN mix compile

# Now build assets (esbuild can resolve phoenix-colocated from _build/prod/)
COPY assets assets
RUN mix assets.deploy

# Build the release
RUN mix release

# Stage 2: Runtime
FROM debian:bookworm-slim AS runner

RUN apt-get update -y && apt-get install -y \
  libstdc++6 \
  openssl \
  libncurses5 \
  locales \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

RUN useradd --create-home app
USER app

# Copy the release from builder
COPY --from=builder --chown=app:app /app/_build/prod/rel/mobile_car_wash ./

ENV PHX_SERVER=true

EXPOSE 8080

CMD ["bin/mobile_car_wash", "start"]
