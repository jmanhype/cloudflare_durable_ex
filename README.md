# CloudflareDurable

[![Hex.pm](https://img.shields.io/hexpm/v/cloudflare_durable.svg)](https://hex.pm/packages/cloudflare_durable)
[![Build Status](https://github.com/jmanhype/cloudflare_durable_ex/workflows/CI/badge.svg)](https://github.com/jmanhype/cloudflare_durable_ex/actions)

Elixir client for Cloudflare Durable Objects. Provides HTTP and WebSocket interfaces for remote state management, method invocation, and real-time updates.

## What it does

- Initialize Durable Objects with a starting state
- Call methods on remote Durable Objects via HTTP
- Open WebSocket connections for bidirectional real-time communication
- Automatic reconnection and transparent error handling
- Telemetry events for observability
- Phoenix adapter for Channels, LiveView, PubSub, and Presence integration

## Requirements

- Elixir >= 1.14
- A deployed Cloudflare Worker with Durable Objects (reference implementation included in `priv/cloudflare/`)

## Installation

Add to `mix.exs`:

```elixir
def deps do
  [
    {:cloudflare_durable, "~> 0.2.0"}
  ]
end
```

Then run `mix deps.get`.

## Configuration

```elixir
# config/config.exs
config :cloudflare_durable,
  worker_url: System.get_env("CLOUDFLARE_WORKER_URL"),
  account_id: System.get_env("CLOUDFLARE_ACCOUNT_ID"),
  api_token: System.get_env("CLOUDFLARE_API_TOKEN"),
  timeout: 30_000,
  retry_count: 3,
  retry_delay: 500,
  websocket_reconnect_delay: 1_000,
  pool_size: 10
```

| Variable | Description |
|---|---|
| `CLOUDFLARE_WORKER_URL` | URL of your deployed Cloudflare Worker |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare account ID |
| `CLOUDFLARE_API_TOKEN` | API token with appropriate permissions |

## Usage

### Initialize and call methods

```elixir
alias CloudflareDurable.Client

{:ok, _} = Client.initialize("counter", %{value: 0})
{:ok, result} = Client.call_method("counter", "increment", %{increment: 1})
# result => %{"value" => 1}
```

### WebSocket connection

```elixir
{:ok, socket} = Client.open_websocket("counter")

CloudflareDurable.WebSocket.Connection.register_handler(socket, fn message ->
  IO.puts("Received: #{inspect(message)}")
end)

CloudflareDurable.websocket_send(socket, Jason.encode!(%{type: "update", value: 42}))
CloudflareDurable.websocket_close(socket)
```

### Phoenix integration

The library includes a Phoenix adapter for Channels, LiveView, and Presence. See `lib/cloudflare_durable/phoenix/README.md` for setup.

## Deploying the Worker

A reference Cloudflare Worker is in `priv/cloudflare/`:

```bash
npm install -g wrangler
wrangler login
cd priv/cloudflare && wrangler publish
```

## Telemetry events

| Event | When |
|---|---|
| `[:cloudflare_durable, :request, :start]` | Request begins |
| `[:cloudflare_durable, :request, :stop]` | Request completes |
| `[:cloudflare_durable, :websocket, :connected]` | WebSocket connected |
| `[:cloudflare_durable, :websocket, :disconnected]` | WebSocket closed |
| `[:cloudflare_durable, :error]` | Error occurs |

## Benchmarking

```bash
mix benchmark             # All benchmarks
mix benchmark http        # HTTP only
mix benchmark websocket   # WebSocket only
mix benchmark state       # State operations only
```

Configure with environment variables: `BENCHMARK_WORKER_URL`, `BENCHMARK_CONCURRENCY` (default: 4), `BENCHMARK_DURATION` (default: 5s).

## Project structure

```
lib/
  cloudflare_durable.ex        # Main module
  cloudflare_durable/
    client.ex                  # HTTP client
    http.ex                    # HTTP layer
    websocket.ex               # WebSocket client
    websocket/connection.ex    # Connection management
    websocket/supervisor.ex    # Supervision tree
    phoenix.ex                 # Phoenix adapter
    phoenix/                   # Channel, LiveView, Presence modules
    benchmark/                 # Benchmarking tools
examples/                      # Counter, collaborative doc, WebSocket examples
benchmarks/                    # Benchee benchmark scripts
```

## License

MIT
