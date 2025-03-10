defmodule CloudflareDurable.WebSocket.Supervisor do
  @moduledoc """
  Supervisor for WebSocket connections to Durable Objects.
  
  This supervisor manages the lifecycle of WebSocket connections to Cloudflare Durable Objects.
  """
  use DynamicSupervisor

  @doc """
  Starts the supervisor.
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a WebSocket connection to a Durable Object.
  
  ## Parameters
    * `object_id` - The ID of the Durable Object to connect to
    * `opts` - Options for the WebSocket connection
  
  ## Returns
    * `{:ok, pid}` - Successfully started WebSocket connection
    * `{:error, reason}` - Failed to start WebSocket connection
  """
  def start_connection(object_id, opts \\ []) do
    DynamicSupervisor.start_child(__MODULE__, {CloudflareDurable.WebSocket.Connection, [object_id, opts]})
  end

  @doc """
  Stops a WebSocket connection.
  
  ## Parameters
    * `pid` - The PID of the WebSocket connection to stop
  
  ## Returns
    * `:ok` - Successfully stopped WebSocket connection
  """
  def stop_connection(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end 