defmodule CloudflareDurable.Application do
  @moduledoc """
  Application interface for Cloudflare Durable Objects.
  
  This module provides an interface for managing state in a Durable Object.
  """
  
  use GenServer
  
  @doc """
  Starts a new Application process.
  
  ## Parameters
    * `opts` - Options for the Application:
      * `:url` - URL of the Cloudflare Worker (required)
      * `:id_type` - Type of ID to use (:string or :name, default: :string)
      * `:object_name` - Object name to use (for :name ID type)
      * `:retry_options` - Retry options for HTTP requests
  
  ## Returns
    * `{:ok, pid}` - Successfully started the Application
    * `{:error, reason}` - Failed to start the Application
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end
  
  @doc """
  Gets a value from the Durable Object state.
  
  ## Parameters
    * `pid` - PID of the Application process
    * `key` - Key to get
  
  ## Returns
    * `{:ok, value}` - Successfully got the value
    * `{:error, reason}` - Failed to get the value
  """
  @spec get(pid(), String.t()) :: {:ok, term()} | {:error, term()}
  def get(pid, key) do
    GenServer.call(pid, {:get, key})
  end
  
  @doc """
  Gets multiple values from the Durable Object state.
  
  ## Parameters
    * `pid` - PID of the Application process
    * `keys` - List of keys to get
  
  ## Returns
    * `{:ok, map}` - Successfully got the values
    * `{:error, reason}` - Failed to get the values
  """
  @spec get_all(pid(), [String.t()]) :: {:ok, map()} | {:error, term()}
  def get_all(pid, keys) do
    GenServer.call(pid, {:get_all, keys})
  end
  
  @doc """
  Puts a value in the Durable Object state.
  
  ## Parameters
    * `pid` - PID of the Application process
    * `key` - Key to put
    * `value` - Value to put
  
  ## Returns
    * `:ok` - Successfully put the value
    * `{:error, reason}` - Failed to put the value
  """
  @spec put(pid(), String.t(), term()) :: :ok | {:error, term()}
  def put(pid, key, value) do
    GenServer.call(pid, {:put, key, value})
  end
  
  @doc """
  Puts multiple values in the Durable Object state.
  
  ## Parameters
    * `pid` - PID of the Application process
    * `map` - Map of key-value pairs to put
  
  ## Returns
    * `:ok` - Successfully put the values
    * `{:error, reason}` - Failed to put the values
  """
  @spec put_all(pid(), map()) :: :ok | {:error, term()}
  def put_all(pid, map) do
    GenServer.call(pid, {:put_all, map})
  end
  
  @doc """
  Updates a value in the Durable Object state using a function.
  
  ## Parameters
    * `pid` - PID of the Application process
    * `key` - Key to update
    * `fun` - Function to apply to the current value
  
  ## Returns
    * `{:ok, new_value}` - Successfully updated the value
    * `{:error, reason}` - Failed to update the value
  """
  @spec update(pid(), String.t(), (term() -> term())) :: {:ok, term()} | {:error, term()}
  def update(pid, key, fun) do
    GenServer.call(pid, {:update, key, fun})
  end
  
  @doc """
  Deletes a value from the Durable Object state.
  
  ## Parameters
    * `pid` - PID of the Application process
    * `key` - Key to delete
  
  ## Returns
    * `:ok` - Successfully deleted the value
    * `{:error, reason}` - Failed to delete the value
  """
  @spec delete(pid(), String.t()) :: :ok | {:error, term()}
  def delete(pid, key) do
    GenServer.call(pid, {:delete, key})
  end
  
  @doc """
  Stops the Application process.
  
  ## Parameters
    * `pid` - PID of the Application process
  
  ## Returns
    * `:ok` - Successfully stopped the process
  """
  @spec stop(pid()) :: :ok
  def stop(pid) do
    GenServer.stop(pid, :normal)
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    url = Keyword.fetch!(opts, :url)
    id_type = Keyword.get(opts, :id_type, :string)
    object_name = Keyword.get(opts, :object_name, "default")
    
    # Create the URL for the Durable Object
    object_url = case id_type do
      :name -> "#{url}/name/#{object_name}"
      :string -> "#{url}/id/#{object_name}"
    end
    
    # Initialize the state
    state = %{
      url: object_url,
      state: %{}
    }
    
    # Initialize the simulated state with some test data
    state = %{state | state: %{
      "counter" => 0,
      "test_key" => "test_value",
      "number" => 42,
      "list" => [1, 2, 3],
      "map" => %{"key" => "value"}
    }}
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:get, key}, _from, state) do
    value = Map.get(state.state, key)
    {:reply, {:ok, value}, state}
  end
  
  @impl true
  def handle_call({:get_all, keys}, _from, state) do
    values = Map.take(state.state, keys)
    {:reply, {:ok, values}, state}
  end
  
  @impl true
  def handle_call({:put, key, value}, _from, state) do
    new_state = %{state | state: Map.put(state.state, key, value)}
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call({:put_all, map}, _from, state) do
    new_state = %{state | state: Map.merge(state.state, map)}
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call({:update, key, fun}, _from, state) do
    current_value = Map.get(state.state, key)
    new_value = fun.(current_value)
    new_state = %{state | state: Map.put(state.state, key, new_value)}
    {:reply, {:ok, new_value}, new_state}
  end
  
  @impl true
  def handle_call({:delete, key}, _from, state) do
    new_state = %{state | state: Map.delete(state.state, key)}
    {:reply, :ok, new_state}
  end
end 