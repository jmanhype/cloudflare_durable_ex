defmodule CloudflareDurable.Client do
  @moduledoc """
  Client for interacting with Cloudflare Durable Objects.
  
  This module provides functions for communicating with Cloudflare Workers and Durable Objects,
  allowing applications to leverage edge-located, stateful storage and processing.
  """
  require Logger
  alias CloudflareDurable.WebSocket

  @type t :: module()
  @type object_id :: String.t()
  @type method_name :: String.t()
  @type http_method :: :get | :post | :put | :delete
  @type http_status :: non_neg_integer()
  @type http_headers :: [{String.t(), String.t()}]
  @type http_body :: String.t() | nil
  @type http_response :: %{status: http_status, body: map() | nil, headers: http_headers}
  @type error_reason :: :network_error | :invalid_response | :server_error | :not_found | atom() | String.t()
  @type client_opts :: [
    worker_url: String.t(),
    api_token: String.t(),
    name: atom(),
    finch_pool_size: pos_integer(),
    finch_pool_count: pos_integer()
  ]
  @type connection_opts :: [
    url: String.t(),
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
  def initialize(object_id, data, opts \\ []) do
    # Validate input parameters
    cond do
      is_nil(object_id) or not is_binary(object_id) ->
        {:error, :invalid_object_id}
      
      is_nil(data) or not is_map(data) ->
        {:error, :invalid_data}
      
      true ->
        worker_url = Keyword.get(opts, :worker_url, default_worker_url())
        
        :telemetry.span(
          [:cloudflare_durable, :request],
          %{object_id: object_id, operation: :initialize},
          fn ->
            Logger.debug("Initializing Durable Object: #{object_id}")
            
            result = make_request(worker_url, "/initialize/#{object_id}", :post, Jason.encode!(data))
            {result, %{object_id: object_id, operation: :initialize}}
          end
        )
    end
  end

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
  @spec call_method(object_id(), method_name(), map(), keyword()) :: {:ok, map()} | {:error, error_reason()}
  def call_method(object_id, method, params, opts \\ []) do
    # Validate input parameters
    cond do
      is_nil(object_id) or not is_binary(object_id) ->
        {:error, :invalid_object_id}
      
      is_nil(method) or not is_binary(method) ->
        {:error, :invalid_method_name}
      
      is_nil(params) or not is_map(params) ->
        {:error, :invalid_params}
      
      true ->
        worker_url = Keyword.get(opts, :worker_url, default_worker_url())
        
        :telemetry.span(
          [:cloudflare_durable, :request],
          %{object_id: object_id, method: method},
          fn ->
            Logger.debug("Calling method #{method} on Durable Object: #{object_id}")
            
            path = "/object/#{object_id}/method/#{method}"
            body = Jason.encode!(params)
            
            result = make_request(worker_url, path, :post, body)
            {result, %{object_id: object_id, method: method}}
          end
        )
    end
  end

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
  @spec open_websocket(object_id(), keyword()) :: {:ok, pid()} | {:error, error_reason()}
  def open_websocket(object_id, opts \\ []) do
    worker_url = Keyword.get(opts, :worker_url, default_worker_url())
    
    # Replace http/https with ws/wss
    ws_url = String.replace(worker_url, ~r/^http(s?):\/\//, "ws\\1://")
    ws_url = "#{ws_url}/object/#{object_id}/websocket"
    
    connection_opts = [
      url: ws_url,
      auto_reconnect: Keyword.get(opts, :auto_reconnect, true),
      backoff_initial: Keyword.get(opts, :backoff_initial, 500),
      backoff_max: Keyword.get(opts, :backoff_max, 30000)
    ]
    
    Logger.debug("Opening WebSocket connection to Durable Object: #{object_id}")
    WebSocket.Supervisor.start_connection(object_id, connection_opts)
  end

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
  @spec get_state(object_id(), String.t() | nil, keyword()) :: {:ok, map()} | {:error, error_reason()}
  def get_state(object_id, key \\ nil, opts \\ []) do
    worker_url = Keyword.get(opts, :worker_url, default_worker_url())
    
    path = if key do
      "/object/#{object_id}/state/#{key}"
    else
      "/object/#{object_id}/state"
    end
    
    :telemetry.span(
      [:cloudflare_durable, :request],
      %{object_id: object_id, operation: :get_state, key: key},
      fn ->
        Logger.debug("Getting state for Durable Object: #{object_id}")
        
        result = make_request(worker_url, path, :get, "")
        {result, %{object_id: object_id, operation: :get_state, key: key}}
      end
    )
  end

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
  @spec update_state(object_id(), String.t(), any(), keyword()) :: {:ok, map()} | {:error, error_reason()}
  def update_state(object_id, key, value, opts \\ []) do
    worker_url = Keyword.get(opts, :worker_url, default_worker_url())
    
    :telemetry.span(
      [:cloudflare_durable, :request],
      %{object_id: object_id, operation: :update_state, key: key},
      fn ->
        Logger.debug("Updating state for Durable Object: #{object_id}, key: #{key}")
        
        path = "/object/#{object_id}/state/#{key}"
        body = Jason.encode!(%{value: value})
        
        result = make_request(worker_url, path, :put, body)
        {result, %{object_id: object_id, operation: :update_state, key: key}}
      end
    )
  end

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
  @spec delete_state(object_id(), String.t(), keyword()) :: {:ok, map()} | {:error, error_reason()}
  def delete_state(object_id, key, opts \\ []) do
    worker_url = Keyword.get(opts, :worker_url, default_worker_url())
    
    :telemetry.span(
      [:cloudflare_durable, :request],
      %{object_id: object_id, operation: :delete_state, key: key},
      fn ->
        Logger.debug("Deleting state for Durable Object: #{object_id}, key: #{key}")
        
        path = "/object/#{object_id}/state/#{key}"
        
        result = make_request(worker_url, path, :delete, "")
        {result, %{object_id: object_id, operation: :delete_state, key: key}}
      end
    )
  end

  @doc """
  Gets a namespace object ID from a namespace and name.
  
  ## Parameters
    * `client` - Client module
    * `namespace` - Durable Object namespace
    * `name` - Name within the namespace
    * `opts` - Optional parameters:
      * `:worker_url` - Override the default worker URL
  
  ## Returns
    * `{:ok, object_id}` - Successfully got object ID
    * `{:error, reason}` - Failed to get object ID
  """
  @spec get_namespace_object(t(), String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, error_reason()}
  def get_namespace_object(_client, namespace, name, opts \\ []) do
    worker_url = Keyword.get(opts, :worker_url, default_worker_url())
    
    :telemetry.span(
      [:cloudflare_durable, :request],
      %{namespace: namespace, name: name, operation: :get_namespace_object},
      fn ->
        Logger.debug("Getting namespace object ID for namespace: #{namespace}, name: #{name}")
        
        path = "/namespace/#{namespace}/id/#{name}"
        
        result = make_request(worker_url, path, :get, "")
        {result, %{namespace: namespace, name: name, operation: :get_namespace_object}}
      end
    )
  end

  @doc """
  Establishes a WebSocket connection to a Durable Object.
  
  ## Parameters
    * `client` - Client module
    * `object_id` - ID of the Durable Object to connect to
    * `path` - Path to connect to
    * `opts` - Connection options:
      * `:subscriber` - PID to receive WebSocket messages
      * `:auto_reconnect` - Whether to automatically reconnect on disconnect (default: true)
      * `:backoff_initial` - Initial backoff time in ms (default: 500)
      * `:backoff_max` - Maximum backoff time in ms (default: 30000)
  
  ## Returns
    * `{:ok, pid}` - Successfully established WebSocket connection
    * `{:error, reason}` - Failed to establish WebSocket connection
  """
  @spec websocket_connect(t(), String.t(), String.t(), keyword()) :: {:ok, pid()} | {:error, error_reason()}
  def websocket_connect(_client, object_id, path, opts \\ []) do
    worker_url = Keyword.get(opts, :worker_url, default_worker_url())
    
    # Replace http/https with ws/wss
    ws_url = String.replace(worker_url, ~r/^http(s?):\/\//, "ws\\1://")
    ws_url = "#{ws_url}/object/#{object_id}/websocket#{path}"
    
    connection_opts = [
      url: ws_url,
      auto_reconnect: Keyword.get(opts, :auto_reconnect, true),
      backoff_initial: Keyword.get(opts, :backoff_initial, 500),
      backoff_max: Keyword.get(opts, :backoff_max, 30000),
      subscriber: Keyword.get(opts, :subscriber)
    ]
    
    Logger.debug("Connecting to WebSocket for Durable Object: #{object_id}, path: #{path}")
    CloudflareDurable.WebSocket.Supervisor.start_connection(object_id, connection_opts)
  end

  # Private functions

  defp default_worker_url do
    Application.get_env(:cloudflare_durable, :worker_url) ||
      raise "Cloudflare Worker URL not configured. Set :worker_url in your application's configuration."
  end

  defp make_request(base_url, path, method, body) do
    url = "#{base_url}#{path}"
    
    request =
      case method do
        :get -> Finch.build(:get, url)
        :post -> Finch.build(:post, url, [{"content-type", "application/json"}], body)
        :put -> Finch.build(:put, url, [{"content-type", "application/json"}], body)
        :delete -> Finch.build(:delete, url)
      end
    
    Logger.debug("Making #{method} request to #{url}")
    if body != "", do: Logger.debug("Request body: #{body}")
    
    case Finch.request(request, CloudflareDurable.Finch) do
      {:ok, %Finch.Response{status: status, body: response_body}} when status in 200..299 ->
        case Jason.decode(response_body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> 
            Logger.error("Invalid response: Failed to parse JSON response")
            :telemetry.execute([:cloudflare_durable, :error], %{count: 1}, %{reason: :json_decode_error})
            {:error, :invalid_response}
        end
        
      {:ok, %Finch.Response{status: status, body: response_body}} ->
        error_reason = case status do
          400 -> :invalid_request
          401 -> :unauthorized
          404 -> :not_found
          429 -> :rate_limited
          500 -> :server_error
          _ -> :http_error
        end
        
        Logger.error("HTTP error #{status}: #{response_body}")
        :telemetry.execute([:cloudflare_durable, :error], %{count: 1}, %{reason: error_reason, status: status})
        {:error, error_reason}
        
      {:error, %Mint.TransportError{reason: reason}} ->
        Logger.error("Network error occurred during request: #{inspect(reason)}")
        :telemetry.execute([:cloudflare_durable, :error], %{count: 1}, %{reason: :network_error})
        {:error, :network_error}
        
      {:error, _} = error ->
        Logger.error("Unknown error occurred during request")
        :telemetry.execute([:cloudflare_durable, :error], %{count: 1}, %{reason: :unknown_error})
        error
    end
  end
end 