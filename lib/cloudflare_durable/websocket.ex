defmodule CloudflareDurable.WebSocket do
  @moduledoc """
  Simple interface for connecting to WebSocket endpoints in Cloudflare Durable Objects.
  
  This module provides functions for connecting to, sending messages to, and closing
  WebSocket connections to Durable Objects.
  """
  require Logger
  
  @type connection :: pid()
  @type message :: String.t()
  @type error_reason :: :connection_failed | :timeout | :network_error | atom() | String.t()
  
  @doc """
  Connects to a WebSocket endpoint.
  
  ## Parameters
    * `url` - URL of the WebSocket endpoint
    
  ## Returns
    * `{:ok, connection}` - Successfully connected to the WebSocket
    * `{:error, reason}` - Failed to connect to the WebSocket
  """
  @spec connect(String.t()) :: {:ok, connection()} | {:error, error_reason()}
  def connect(url) do
    Logger.debug("Connecting to WebSocket: #{url}")
    
    # In a real implementation, this would establish a WebSocket connection
    # For now, we'll simulate a connection by sending a message after a delay
    _state = %{
      url: url,
      connected: true
    }
    
    # Simulate a successful connection
    Process.send_after(self(), {:websocket_connected, self()}, 10)
    
    {:ok, self()}
  end
  
  @doc """
  Sends a message over a WebSocket connection.

  ## Parameters
    * `connection` - WebSocket connection
    * `message` - Message to send

  ## Returns
    * `:ok` - Message sent successfully
    * `{:error, reason}` - Failed to send message
  """
  @spec send(connection(), message()) :: :ok | {:error, error_reason()}
  def send(connection, message) when is_pid(connection) and is_binary(message) do
    Logger.debug("Sending WebSocket message: #{message}")

    # In a real implementation, this would send a message over the WebSocket
    # For now, we'll simulate different types of responses based on the message

    # Parse the message to determine the response
    case safe_decode_json(message) do
      {:ok, %{"type" => "echo"} = decoded} ->
        # Echo the data back
        data = Map.get(decoded, "data", "")
        id = Map.get(decoded, "id", "")
        
        # Simulate a response
        Process.send_after(
          self(),
          {:websocket_message, connection, Jason.encode!(%{
            type: "echo_response",
            id: id,
            data: data
          })},
          10
        )
        
      {:ok, %{"type" => "get"} = decoded} ->
        # Get a value
        key = Map.get(decoded, "key", "")
        id = Map.get(decoded, "id", "")
        
        # Simulate a response
        Process.send_after(
          self(),
          {:websocket_message, connection, Jason.encode!(%{
            type: "get_response",
            id: id,
            key: key,
            value: "value_#{key}"
          })},
          10
        )
        
      {:ok, %{"type" => "set"} = decoded} ->
        # Set a value
        key = Map.get(decoded, "key", "")
        value = Map.get(decoded, "value", "")
        id = Map.get(decoded, "id", "")
        
        # Simulate a response
        Process.send_after(
          self(),
          {:websocket_message, connection, Jason.encode!(%{
            type: "set_response",
            id: id,
            key: key,
            value: value
          })},
          10
        )
        
      {:ok, %{"type" => "error"}} ->
        # Simulate an error
        Process.send_after(
          self(),
          {:websocket_error, connection, "error requested"},
          10
        )
        
      {:ok, %{"type" => "close"}} ->
        # Simulate a close
        Process.send_after(
          self(),
          {:websocket_closed, connection},
          10
        )
        
      {:ok, _} ->
        # Unknown message type
        Process.send_after(
          self(),
          {:websocket_message, connection, Jason.encode!(%{
            type: "unknown_command"
          })},
          10
        )
        
      {:error, reason} ->
        # Invalid JSON
        Logger.warning("Failed to parse WebSocket message: #{inspect(reason)}")
        Process.send_after(
          self(),
          {:websocket_error, connection, "invalid JSON"},
          10
        )
    end

    :ok
  rescue
    error ->
      Logger.error("Error sending WebSocket message: #{inspect(error)}")
      {:error, :send_failed}
  end

  def send(_connection, _message) do
    Logger.warning("Invalid send parameters: connection must be a PID and message must be a string")
    {:error, :invalid_parameters}
  end
  
  @doc """
  Closes a WebSocket connection.

  ## Parameters
    * `connection` - WebSocket connection

  ## Returns
    * `:ok` - Connection closed successfully
    * `{:error, reason}` - Failed to close connection
  """
  @spec close(connection()) :: :ok | {:error, error_reason()}
  def close(connection) when is_pid(connection) do
    Logger.debug("Closing WebSocket connection")

    # In a real implementation, this would close the WebSocket connection
    # For now, we'll simulate a close by sending a message
    Process.send_after(self(), {:websocket_closed, connection}, 10)

    :ok
  rescue
    error ->
      Logger.error("Error closing WebSocket connection: #{inspect(error)}")
      {:error, :close_failed}
  end

  def close(_connection) do
    Logger.warning("Invalid connection parameter: must be a PID")
    {:error, :invalid_connection}
  end

  # Private helpers

  @spec safe_decode_json(String.t()) :: {:ok, map()} | {:error, term()}
  defp safe_decode_json(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      {:ok, _non_map} -> {:error, :expected_object}
      {:error, _} = error -> error
    end
  rescue
    error ->
      Logger.error("JSON decode exception: #{inspect(error)}")
      {:error, :decode_exception}
  end

  defp safe_decode_json(_non_binary) do
    {:error, :invalid_json_input}
  end
end 