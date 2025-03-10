defmodule ChatApp.Application do
  @moduledoc """
  The main application module for the Chat Application example.
  This starts all necessary processes for the chat application.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Finch HTTP client
      {Finch, name: ChatApp.Finch},
      
      # Start the Phoenix PubSub system
      {Phoenix.PubSub, name: ChatApp.PubSub},
      
      # Start the Chat Room Registry
      {Registry, keys: :unique, name: ChatApp.RoomRegistry},
      
      # Start the Chat Room DynamicSupervisor
      {DynamicSupervisor, strategy: :one_for_one, name: ChatApp.RoomSupervisor},
      
      # Start the Cloudflare Durable Objects client
      {CloudflareDurable.Client,
        worker_url: Application.get_env(:chat_app, :cloudflare_worker_url),
        api_token: Application.get_env(:chat_app, :cloudflare_api_token),
        name: ChatApp.DurableClient
      },
      
      # Start the Telemetry supervisor
      ChatApp.Telemetry,
      
      # Start the Endpoint (HTTP server)
      ChatApp.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ChatApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end 