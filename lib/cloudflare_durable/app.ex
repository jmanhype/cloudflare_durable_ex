defmodule CloudflareDurable.App do
  @moduledoc """
  Application module for CloudflareDurable.
  
  This module starts the necessary processes for the CloudflareDurable application,
  including the WebSocket supervisor and Finch HTTP client pool.
  """
  use Application

  @type start_type :: :normal | {:takeover, node()} | {:failover, node()}
  @type start_args :: term()
  
  @doc """
  Starts the CloudflareDurable application.
  
  ## Parameters
    * `type` - Start type (e.g., :normal, {:takeover, node()}, {:failover, node()})
    * `args` - Start arguments
  
  ## Returns
    * `{:ok, pid}` - Successfully started the application supervisor
    * `{:error, reason}` - Failed to start the application
  """
  @spec start(start_type(), start_args()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    children = [
      # HTTP client for making requests to Cloudflare
      {Finch, name: CloudflareDurable.Finch}
      # Supervisor for WebSocket connections
      # {CloudflareDurable.WebSocket.Supervisor, []}
    ]

    opts = [strategy: :one_for_one, name: CloudflareDurable.Supervisor]
    Supervisor.start_link(children, opts)
  end
end 