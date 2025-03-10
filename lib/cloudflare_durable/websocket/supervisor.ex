defmodule CloudflareDurable.WebSocket.Supervisor do
  @moduledoc """
  Supervisor for WebSocket connections to Durable Objects.
  
  This supervisor manages the lifecycle of WebSocket connections to Cloudflare Durable Objects.
  """
  use DynamicSupervisor

  @type object_id :: String.t()
  @type connection_opts :: [
    url: String.t(),
    auto_reconnect: boolean(),
    backoff_initial: non_neg_integer(),
    backoff_max: non_neg_integer()
  ]
  @type supervisor_opts :: keyword()
  @type error_reason :: :already_started | :shutdown | :timeout | term()

  @doc """
  Starts the supervisor.
  
  ## Parameters
    * `init_arg` - Initialization arguments for the supervisor
    
  ## Returns
    * `{:ok, pid}` - Successfully started the supervisor
    * `{:error, reason}` - Failed to start the supervisor
  """
  @spec start_link(supervisor_opts()) :: {:ok, pid()} | {:error, term()}
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  @spec init(supervisor_opts()) :: {:ok, DynamicSupervisor.sup_flags()}
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a WebSocket connection to a Durable Object.
  
  ## Parameters
    * `object_id` - The ID of the Durable Object to connect to
    * `opts` - Options for the WebSocket connection:
      * `:url` - WebSocket URL
      * `:auto_reconnect` - Whether to automatically reconnect (default: true)
      * `:backoff_initial` - Initial backoff time in ms (default: 500)
      * `:backoff_max` - Maximum backoff time in ms (default: 30000)
  
  ## Returns
    * `{:ok, pid}` - Successfully started WebSocket connection
    * `{:error, reason}` - Failed to start WebSocket connection
  """
  @spec start_connection(object_id(), connection_opts()) :: {:ok, pid()} | {:error, error_reason()}
  def start_connection(object_id, opts \\ []) do
    DynamicSupervisor.start_child(__MODULE__, {CloudflareDurable.WebSocket.Connection, [object_id, opts]})
  end

  @doc """
  Stops a WebSocket connection.
  
  ## Parameters
    * `pid` - The PID of the WebSocket connection to stop
  
  ## Returns
    * `:ok` - Successfully stopped WebSocket connection
    * `{:error, :not_found}` - Connection not found
  """
  @spec stop_connection(pid()) :: :ok | {:error, :not_found}
  def stop_connection(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
  
  @doc """
  Lists all active WebSocket connections.
  
  ## Returns
    * `[pid()]` - List of PIDs for all active WebSocket connections
  """
  @spec list_connections() :: [pid()]
  def list_connections() do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} -> pid end)
  end
end 