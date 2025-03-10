defmodule CloudflareDurable do
  @moduledoc """
  CloudflareDurable is a client for Cloudflare Durable Objects, providing a simple interface
  for distributed state management, WebSocket connections, and method invocation.
  
  This module provides convenience functions that delegate to the underlying Client module.
  
  ## Usage
  
  ```elixir
  # Initialize a new Durable Object
  {:ok, _} = CloudflareDurable.initialize("counter", %{value: 0})
  
  # Call a method on the Durable Object
  {:ok, result} = CloudflareDurable.call_method("counter", "increment", %{increment: 1})
  
  # Open a WebSocket for real-time updates
  {:ok, socket} = CloudflareDurable.open_websocket("counter")
  ```
  """
  
  alias CloudflareDurable.Client
  require Logger
  
  @type object_id :: String.t()
  @type method_name :: String.t()
  @type method_params :: map()
  @type state_key :: String.t() | nil
  @type state_value :: any()
  @type websocket_connection :: pid()
  @type error_reason :: :network_error | :invalid_response | :server_error | :not_found | atom() | String.t()
  @type client_opts :: [
    worker_url: String.t(),
    auto_reconnect: boolean(),
    backoff_initial: non_neg_integer(),
    backoff_max: non_neg_integer(),
    subscriber: pid() | nil
  ]
  
  @doc """
  Initializes a new Durable Object instance.
  
  ## Parameters
    * `object_id` - ID of the Durable Object to initialize
    * `data` - Initial data to store in the Durable Object
    * `opts` - Optional parameters:
      * `:worker_url` - Override the default worker URL
  
  ## Returns
    * `{:ok, response}` - Successfully initialized Durable Object
    * `{:error, reason}` - Failed to initialize Durable Object
  """
  @spec initialize(object_id(), map(), keyword()) :: {:ok, map()} | {:error, error_reason()}
  defdelegate initialize(object_id, data, opts \\ []), to: Client
  
  @doc """
  Calls a method on a Durable Object.
  
  ## Parameters
    * `object_id` - ID of the Durable Object to call
    * `method` - Method to call on the Durable Object
    * `params` - Parameters to pass to the method
    * `opts` - Optional parameters:
      * `:worker_url` - Override the default worker URL
  
  ## Returns
    * `{:ok, response}` - Successfully called method on Durable Object
    * `{:error, reason}` - Failed to call method on Durable Object
  """
  @spec call_method(object_id(), method_name(), method_params(), keyword()) :: 
        {:ok, map()} | {:error, error_reason()}
  defdelegate call_method(object_id, method, params, opts \\ []), to: Client
  
  @doc """
  Opens a WebSocket connection to a Durable Object.
  
  ## Parameters
    * `object_id` - ID of the Durable Object to connect to
    * `opts` - Optional parameters:
      * `:worker_url` - Override the default worker URL
      * `:auto_reconnect` - Whether to automatically reconnect on disconnect (default: true)
      * `:backoff_initial` - Initial backoff time in ms (default: 500)
      * `:backoff_max` - Maximum backoff time in ms (default: 30000)
  
  ## Returns
    * `{:ok, pid}` - Successfully opened WebSocket connection
    * `{:error, reason}` - Failed to open WebSocket connection
  """
  @spec open_websocket(object_id(), client_opts()) :: 
        {:ok, websocket_connection()} | {:error, error_reason()}
  defdelegate open_websocket(object_id, opts \\ []), to: Client
  
  @doc """
  Gets the state of a Durable Object.
  
  ## Parameters
    * `object_id` - ID of the Durable Object to get state from
    * `key` - Optional specific key to get (if nil, gets all state)
    * `opts` - Optional parameters:
      * `:worker_url` - Override the default worker URL
  
  ## Returns
    * `{:ok, state}` - Successfully retrieved state
    * `{:error, reason}` - Failed to retrieve state
  """
  @spec get_state(object_id(), state_key(), keyword()) :: 
        {:ok, map()} | {:error, error_reason()}
  defdelegate get_state(object_id, key \\ nil, opts \\ []), to: Client
  
  @doc """
  Updates the state of a Durable Object.
  
  ## Parameters
    * `object_id` - ID of the Durable Object to update
    * `key` - Key to update
    * `value` - Value to set
    * `opts` - Optional parameters:
      * `:worker_url` - Override the default worker URL
  
  ## Returns
    * `{:ok, response}` - Successfully updated state
    * `{:error, reason}` - Failed to update state
  """
  @spec update_state(object_id(), state_key(), state_value(), keyword()) :: 
        {:ok, map()} | {:error, error_reason()}
  defdelegate update_state(object_id, key, value, opts \\ []), to: Client
  
  @doc """
  Deletes a key from a Durable Object's state.
  
  ## Parameters
    * `object_id` - ID of the Durable Object to update
    * `key` - Key to delete
    * `opts` - Optional parameters:
      * `:worker_url` - Override the default worker URL
  
  ## Returns
    * `{:ok, response}` - Successfully deleted key
    * `{:error, reason}` - Failed to delete key
  """
  @spec delete_state(object_id(), state_key(), keyword()) :: 
        {:ok, map()} | {:error, error_reason()}
  defdelegate delete_state(object_id, key, opts \\ []), to: Client

  @doc """
  Gets a namespace object ID from a namespace and name.
  
  ## Parameters
    * `namespace` - Durable Object namespace
    * `name` - Name within the namespace
    * `opts` - Optional parameters:
      * `:worker_url` - Override the default worker URL
  
  ## Returns
    * `{:ok, object_id}` - Successfully got object ID
    * `{:error, reason}` - Failed to get object ID
  """
  @spec get_namespace_object(String.t(), String.t(), keyword()) :: 
        {:ok, object_id()} | {:error, error_reason()}
  def get_namespace_object(namespace, name, opts \\ []) do
    Client.get_namespace_object(Client, namespace, name, opts)
  end

  @doc """
  Establishes a WebSocket connection to a Durable Object.
  
  ## Parameters
    * `object_id` - ID of the Durable Object to connect to
    * `path` - Path to connect to (default: "/")
    * `opts` - Connection options:
      * `:subscriber` - PID to receive WebSocket messages
      * `:auto_reconnect` - Whether to automatically reconnect on disconnect (default: true)
      * `:backoff_initial` - Initial backoff time in ms (default: 500)
      * `:backoff_max` - Maximum backoff time in ms (default: 30000)
  
  ## Returns
    * `{:ok, pid}` - Successfully established WebSocket connection
    * `{:error, reason}` - Failed to establish WebSocket connection
  """
  @spec websocket_connect(object_id(), String.t(), client_opts()) :: 
        {:ok, websocket_connection()} | {:error, error_reason()}
  def websocket_connect(object_id, path \\ "/", opts \\ []) do
    Client.websocket_connect(Client, object_id, path, opts)
  end

  @doc """
  Sends a message over a WebSocket connection.

  ## Parameters
    * `connection` - WebSocket connection PID
    * `message` - Message to send

  ## Returns
    * `:ok` - Message sent successfully
    * `{:error, reason}` - Failed to send message
  """
  @spec websocket_send(websocket_connection(), String.t()) :: :ok | {:error, error_reason()}
  def websocket_send(connection, message) do
    Logger.debug("Sending WebSocket message: #{inspect(message)}")
    CloudflareDurable.WebSocket.Connection.send_message(connection, message)
  end

  @doc """
  Closes a WebSocket connection.

  ## Parameters
    * `connection` - WebSocket connection PID

  ## Returns
    * `:ok` - Connection closed successfully
    * `{:error, reason}` - Failed to close connection
  """
  @spec websocket_close(websocket_connection()) :: :ok | {:error, error_reason()}
  def websocket_close(connection) do
    Logger.debug("Closing WebSocket connection")
    GenServer.stop(connection, :normal)
    :ok
  end
end 