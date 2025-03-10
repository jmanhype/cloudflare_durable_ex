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
  defdelegate delete_state(object_id, key, opts \\ []), to: Client
end 