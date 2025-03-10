# CloudflareDurable

[![Hex.pm](https://img.shields.io/hexpm/v/cloudflare_durable.svg)](https://hex.pm/packages/cloudflare_durable)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/cloudflare_durable)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Build Status](https://github.com/jmanhype/cloudflare_durable_ex/workflows/CI/badge.svg)](https://github.com/jmanhype/cloudflare_durable_ex/actions)

An Elixir client for Cloudflare Durable Objects, providing a simple interface for distributed state management, WebSocket connections, and method invocation. This library enables Elixir applications to leverage Cloudflare's globally distributed persistent state without managing complex infrastructure.

## Features

- Initialize Durable Objects with initial state
- Call methods on remote Durable Objects
- Establish WebSocket connections for real-time updates
- Transparent error handling and reconnection
- Event-based architecture using Telemetry
- Configurable through standard Elixir configuration
- Type specifications for better development experience

## Installation

Add `cloudflare_durable` to your mix.exs dependencies:

```elixir
def deps do
  [
    {:cloudflare_durable, "~> 0.2.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Configuration

Add the following to your application configuration:

```elixir
# In config/config.exs
config :cloudflare_durable,
  worker_url: System.get_env("CLOUDFLARE_WORKER_URL") || "https://your-worker.your-subdomain.workers.dev",
  account_id: System.get_env("CLOUDFLARE_ACCOUNT_ID"),
  api_token: System.get_env("CLOUDFLARE_API_TOKEN"),
  # Optional settings
  timeout: 30_000,                   # Request timeout in milliseconds
  retry_count: 3,                    # Number of retries for failed requests
  retry_delay: 500,                  # Delay between retries in milliseconds
  websocket_reconnect_delay: 1_000,  # Delay before reconnecting WebSockets
  pool_size: 10                      # HTTP connection pool size
```

### Environment Variables

For production use, we recommend setting the following environment variables:

- `CLOUDFLARE_WORKER_URL`: URL of your deployed Cloudflare Worker
- `CLOUDFLARE_ACCOUNT_ID`: Your Cloudflare account ID
- `CLOUDFLARE_API_TOKEN`: API token with appropriate permissions

## Usage

### Basic Examples

#### Initialize a Durable Object

```elixir
alias CloudflareDurable.Client

# Initialize a new Durable Object with an initial state
{:ok, response} = Client.initialize("counter", %{value: 0})
```

#### Call Methods on a Durable Object

```elixir
# Call a method on the Durable Object
{:ok, result} = Client.call_method("counter", "increment", %{increment: 1})
IO.inspect(result) # => %{"value" => 1}

# Call another method
{:ok, result} = Client.call_method("counter", "get_value", %{})
IO.inspect(result) # => %{"value" => 1}
```

#### Open a WebSocket Connection

```elixir
# Open a WebSocket for real-time updates
{:ok, socket} = Client.open_websocket("counter")

# Register a message handler
CloudflareDurable.WebSocket.Connection.register_handler(socket, fn message ->
  IO.puts("Received message: #{inspect(message)}")
end)

# Send a message through WebSocket
CloudflareDurable.WebSocket.Connection.send_message(socket, %{type: "update", value: 42})
```

### Advanced Examples

#### Distributed Counter

```elixir
defmodule MyApp.DistributedCounter do
  alias CloudflareDurable.Client
  
  @doc """
  Creates a new counter with a starting value
  """
  def create(id, start_value \\ 0) do
    Client.initialize("counter-#{id}", %{value: start_value})
  end
  
  @doc """
  Increments the counter by the given amount
  """
  def increment(id, amount \\ 1) do
    case Client.call_method("counter-#{id}", "increment", %{increment: amount}) do
      {:ok, result} -> {:ok, result["value"]}
      {:error, _} = error -> error
    end
  end
  
  @doc """
  Gets the current value of the counter
  """
  def get_value(id) do
    case Client.call_method("counter-#{id}", "get_value", %{}) do
      {:ok, result} -> {:ok, result["value"]}
      {:error, _} = error -> error
    end
  end
  
  @doc """
  Subscribes to counter updates
  """
  def subscribe(id, pid) do
    with {:ok, socket} <- Client.open_websocket("counter-#{id}") do
      CloudflareDurable.WebSocket.Connection.register_handler(socket, fn message ->
        send(pid, {:counter_update, id, message["value"]})
      end)
      {:ok, socket}
    end
  end
end
```

#### Collaborative Document Editing

```elixir
# Initialize a collaborative document
{:ok, _} = CloudflareDurable.Client.initialize("document-123", %{
  content: "Initial document content",
  version: 1,
  editors: []
})

# Join as an editor
{:ok, result} = CloudflareDurable.Client.call_method("document-123", "join", %{
  editor_id: "user-456",
  name: "John Doe"
})

# Make an edit
{:ok, result} = CloudflareDurable.Client.call_method("document-123", "update", %{
  editor_id: "user-456",
  content: "Updated document content",
  version: 2
})

# Open WebSocket for real-time updates
{:ok, socket} = CloudflareDurable.Client.open_websocket("document-123")
CloudflareDurable.WebSocket.Connection.register_handler(socket, fn message ->
  case message do
    %{"type" => "edit", "editor" => editor, "content" => content, "version" => version} ->
      IO.puts("#{editor} updated the document to version #{version}")
      
    %{"type" => "join", "editor" => editor} ->
      IO.puts("#{editor} joined the document")
      
    %{"type" => "leave", "editor" => editor} ->
      IO.puts("#{editor} left the document")
  end
end)
```

## Deploying the Durable Objects Worker

This library relies on a Cloudflare Worker script that handles the Durable Objects. A reference implementation is included in the `priv/cloudflare` directory.

1. Install Wrangler (Cloudflare's CLI tool):
   ```bash
   npm install -g wrangler
   ```

2. Authenticate with Cloudflare:
   ```bash
   wrangler login
   ```

3. Deploy the Worker and Durable Object:
   ```bash
   cd priv/cloudflare
   wrangler publish
   ```

4. Note the URL of your deployed worker and update your configuration.

### Reference Worker Implementation

The reference implementation in the `priv/cloudflare` directory provides:

- REST API for Durable Object method invocation
- WebSocket connections to Durable Objects
- User-defined method handlers
- Persistence of Durable Object state

## Telemetry Metrics

This library emits telemetry events that you can subscribe to:

- `[:cloudflare_durable, :request, :start]` - When a request to a Durable Object starts
- `[:cloudflare_durable, :request, :stop]` - When a request to a Durable Object completes
- `[:cloudflare_durable, :websocket, :connected]` - When a WebSocket connection is established
- `[:cloudflare_durable, :websocket, :disconnected]` - When a WebSocket connection is closed
- `[:cloudflare_durable, :error]` - When an error occurs

### Example Telemetry Setup

```elixir
defmodule MyApp.Telemetry do
  def setup do
    :telemetry.attach(
      "cloudflare-durable-request-handler",
      [:cloudflare_durable, :request, :stop],
      &handle_request_event/4,
      nil
    )
    
    :telemetry.attach(
      "cloudflare-durable-error-handler",
      [:cloudflare_durable, :error],
      &handle_error_event/4,
      nil
    )
  end
  
  defp handle_request_event(_event, measurements, metadata, _config) do
    # Log or record metrics about requests
    IO.puts("Request to #{metadata.object_id}##{metadata.method} completed in #{measurements.duration} ms")
  end
  
  defp handle_error_event(_event, _measurements, metadata, _config) do
    # Log or record error metrics
    IO.puts("Error in CloudflareDurable: #{inspect(metadata.error)}")
  end
end
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This package is licensed under the MIT License - see the [LICENSE](LICENSE) file for details. 