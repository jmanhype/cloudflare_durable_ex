defmodule CloudflareDurable.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # HTTP client for making requests to Cloudflare
      {Finch, name: CloudflareDurable.Finch},
      # Supervisor for WebSocket connections
      {CloudflareDurable.WebSocket.Supervisor, []}
    ]

    opts = [strategy: :one_for_one, name: CloudflareDurable.Supervisor]
    Supervisor.start_link(children, opts)
  end
end 