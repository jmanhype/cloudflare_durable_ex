defmodule CloudflareDurable.Phoenix.DurableServer do
  @moduledoc """
  GenServer representation of a Cloudflare Durable Object.
  
  This module provides a local representation of Durable Objects,
  handling state synchronization, caching, and event broadcasting.
  It communicates with Cloudflare's edge network to maintain
  consistency with the remote Durable Object.
  """
  
  use GenServer
  require Logger
  alias CloudflareDurable.Client
  
  @type server :: GenServer.server()
  @type object_id :: String.t()
  @type key :: String.t()
  @type value :: any()
  @type state :: %{
    object_id: object_id(),
    cache: map(),
    last_updated: integer() | nil,
    connected: boolean(),
    connection_attempts: non_neg_integer(),
    opts: keyword()
  }
  
  # Client API
  
  @doc """
  Starts a DurableServer for the given object_id.
  
  ## Options
  
  * `:refresh_interval` - Milliseconds between state refreshes (default: 10000)
  * `:name` - Optional name for the process
  
  ## Returns
  
  * `{:ok, pid}` - If the server was started successfully
  * `{:error, reason}` - If the server could not be started
  """
  @spec start_link(object_id(), keyword()) :: GenServer.on_start()
  def start_link(object_id, opts \\ []) do
    name = opts[:name] || via_tuple(object_id)
    GenServer.start_link(__MODULE__, {object_id, opts}, name: name)
  end
  
  @doc """
  Gets the current state of the Durable Object.
  
  ## Parameters
  
  * `server` - The DurableServer process
  * `key` - Optional specific key to retrieve (nil returns full state)
  
  ## Returns
  
  * `{:ok, value}` - The value of the requested key or full state map
  * `{:error, reason}` - If there was an error retrieving the state
  """
  @spec get_state(server(), key() | nil) :: {:ok, any()} | {:error, term()}
  def get_state(server, key \\ nil) do
    GenServer.call(server, {:get_state, key})
  end
  
  @doc """
  Updates a key in the Durable Object's state.
  
  This updates both the remote Durable Object and the local cache,
  and broadcasts the change to all subscribers.
  
  ## Parameters
  
  * `server` - The DurableServer process
  * `key` - The key to update
  * `value` - The new value
  
  ## Returns
  
  * `:ok` - If the update was successful
  * `{:error, reason}` - If there was an error updating the state
  """
  @spec update_state(server(), key(), value()) :: :ok | {:error, term()}
  def update_state(server, key, value) do
    GenServer.call(server, {:update_state, key, value})
  end
  
  @doc """
  Calls a method on the Durable Object.
  
  ## Parameters
  
  * `server` - The DurableServer process
  * `method` - The method to call
  * `params` - Parameters to pass to the method
  
  ## Returns
  
  * `{:ok, result}` - The result of the method call
  * `{:error, reason}` - If there was an error calling the method
  """
  @spec call_method(server(), String.t(), map()) :: {:ok, any()} | {:error, term()}
  def call_method(server, method, params \\ %{}) do
    GenServer.call(server, {:call_method, method, params})
  end
  
  @doc """
  Refreshes the local cache with the current Durable Object state.
  """
  @spec refresh_state(server()) :: :ok
  def refresh_state(server) do
    GenServer.cast(server, :refresh_state)
  end
  
  @doc """
  Gets the server process for an object_id from the registry.
  """
  @spec via_tuple(object_id()) :: {:via, Registry, {CloudflareDurable.Phoenix.Registry, object_id()}}
  def via_tuple(object_id) do
    {:via, Registry, {CloudflareDurable.Phoenix.Registry, object_id}}
  end
  
  # GenServer Callbacks
  
  @impl true
  def init({object_id, opts}) do
    Process.flag(:trap_exit, true)
    
    state = %{
      object_id: object_id,
      cache: %{},
      last_updated: nil,
      connected: false,
      connection_attempts: 0,
      opts: opts
    }
    
    # Start with an immediate state refresh
    send(self(), :refresh_state)
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:get_state, nil}, _from, %{cache: cache} = state) do
    {:reply, {:ok, cache}, state}
  end
  
  @impl true
  def handle_call({:get_state, key}, _from, %{cache: cache} = state) do
    result = 
      case Map.fetch(cache, key) do
        {:ok, value} -> {:ok, value}
        :error -> {:error, :not_found}
      end
    
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:update_state, key, value}, _from, %{object_id: object_id} = state) do
    case Client.update_state(object_id, key, value) do
      {:ok, _} ->
        new_cache = Map.put(state.cache, key, value)
        new_state = %{state | 
          cache: new_cache, 
          last_updated: System.monotonic_time(),
          connected: true,
          connection_attempts: 0
        }
        
        # Broadcast the update
        broadcast_update(object_id, %{key => value})
        
        {:reply, :ok, new_state}
        
      error ->
        Logger.error("Failed to update Durable Object state: #{inspect(error)}")
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:call_method, method, params}, _from, %{object_id: object_id} = state) do
    case Client.call_method(object_id, method, params) do
      {:ok, result} ->
        # If the method changed state, refresh our cache
        send(self(), :refresh_state)
        {:reply, {:ok, result}, %{state | connected: true, connection_attempts: 0}}
        
      error ->
        Logger.error("Failed to call method on Durable Object: #{inspect(error)}")
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_cast(:refresh_state, state) do
    send(self(), :refresh_state)
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:refresh_state, %{object_id: object_id} = state) do
    case Client.get_state(object_id) do
      {:ok, new_state} ->
        updated_state = %{
          state | 
          cache: new_state,
          last_updated: System.monotonic_time(),
          connected: true,
          connection_attempts: 0
        }
        
        # Broadcast full state update if it changed
        if new_state != state.cache do
          broadcast_update(object_id, new_state)
        end
        
        # Schedule next refresh
        Process.send_after(self(), :refresh_state, refresh_interval(state.opts))
        
        {:noreply, updated_state}
        
      {:error, reason} ->
        Logger.warn("Failed to refresh Durable Object state: #{inspect(reason)}")
        
        # Back off on errors
        new_attempts = state.connection_attempts + 1
        backoff = min(30_000, 1000 * :math.pow(2, new_attempts))
        
        Process.send_after(self(), :refresh_state, round(backoff))
        
        {:noreply, %{state | connection_attempts: new_attempts, connected: false}}
    end
  end
  
  @impl true
  def terminate(_reason, %{object_id: object_id}) do
    # Clean up any resources associated with this Durable Object
    Logger.info("Terminating DurableServer for object #{object_id}")
    :ok
  end
  
  # Private helpers
  
  defp refresh_interval(opts) do
    Keyword.get(opts, :refresh_interval, 10_000)
  end
  
  defp broadcast_update(object_id, update) do
    Phoenix.PubSub.broadcast(
      CloudflareDurable.Phoenix.PubSub,
      "durable_object:#{object_id}",
      {:durable_object_update, object_id, update}
    )
  end
end 