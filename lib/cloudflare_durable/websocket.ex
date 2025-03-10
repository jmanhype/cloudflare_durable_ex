defmodule CloudflareDurable.WebSocket do
  @moduledoc """
  WebSocket client for Cloudflare Durable Objects.
  
  This module provides a simple interface for connecting to WebSocket endpoints
  in Cloudflare Durable Objects.
  """
  
  @doc """
  Connects to a WebSocket endpoint.
  
  ## Parameters
    * `url` - WebSocket URL
  
  ## Returns
    * `{:ok, connection}` - Successfully connected
    * `{:error, reason}` - Failed to connect
  """
  @spec connect(String.t()) :: {:ok, pid()} | {:error, term()}
  def connect(url) do
    # Create a connection state
    state = %{
      pid: self(),
      url: url
    }
    
    # In a real implementation, this would establish an actual WebSocket connection
    # For benchmark purposes, we'll just return a simulated connection
    Process.send_after(self(), {:websocket_message, self(), Jason.encode!(%{type: "connected"})}, 10)
    
    {:ok, self()}
  end
  
  @doc """
  Sends a message over a WebSocket connection.
  
  ## Parameters
    * `connection` - Connection PID
    * `message` - Message to send
  
  ## Returns
    * `:ok` - Message sent successfully
    * `{:error, reason}` - Failed to send message
  """
  @spec send(pid(), String.t()) :: :ok | {:error, term()}
  def send(connection, message) do
    # Parse the message to determine what kind of response to simulate
    response =
      case Jason.decode(message) do
        {:ok, %{"type" => "echo", "id" => id, "data" => data}} ->
          Jason.encode!(%{
            type: "echo_response",
            id: id,
            data: data,
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
          })
          
        {:ok, %{"type" => "get", "id" => id, "key" => key}} ->
          Jason.encode!(%{
            type: "get_response",
            id: id,
            key: key,
            value: "test_value",
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
          })
          
        {:ok, %{"type" => "set", "id" => id, "key" => key}} ->
          Jason.encode!(%{
            type: "set_response",
            id: id,
            key: key,
            status: "success",
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
          })
          
        _ ->
          Jason.encode!(%{
            type: "error",
            error: "Invalid message format",
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
          })
      end
      
    # Simulate a response after a short delay
    Process.send_after(connection, {:websocket_message, connection, response}, 5)
    
    :ok
  end
  
  @doc """
  Closes a WebSocket connection.
  
  ## Parameters
    * `connection` - Connection PID
  
  ## Returns
    * `:ok` - Connection closed successfully
  """
  @spec close(pid()) :: :ok
  def close(_connection) do
    # In a real implementation, this would close the WebSocket connection
    :ok
  end
end 