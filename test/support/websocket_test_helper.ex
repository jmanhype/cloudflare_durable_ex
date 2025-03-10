defmodule CloudflareDurable.WebSocketTestHelper do
  @moduledoc """
  Helper functions for testing WebSocket connections in CloudflareDurable.
  
  This module provides utilities for mocking WebSocket connections and
  simulating WebSocket events in tests.
  """
  
  alias CloudflareDurable.WebSocket
  
  @doc """
  Creates a mock WebSocket connection for testing.
  
  ## Parameters
  
  * `test_pid` - The PID of the test process (usually `self()`)
  * `opts` - Options to customize the mock connection:
    * `:auto_respond` - Whether to automatically respond to messages (default: `true`)
    * `:simulate_errors` - Whether to simulate connection errors (default: `false`)
  
  ## Returns
  
  * `{:ok, pid()}` - A simulated WebSocket connection PID
  """
  @spec create_mock_connection(pid(), keyword()) :: {:ok, pid()}
  def create_mock_connection(test_pid, opts \\ []) do
    auto_respond = Keyword.get(opts, :auto_respond, true)
    simulate_errors = Keyword.get(opts, :simulate_errors, false)
    
    # Spawn a process that simulates a WebSocket connection
    connection_pid = spawn(fn -> mock_connection_loop(test_pid, auto_respond, simulate_errors) end)
    
    # Send a connected message to the test process
    if !simulate_errors do
      Process.send_after(
        test_pid, 
        {:websocket_message, connection_pid, Jason.encode!(%{type: "connected"})}, 
        10
      )
    end
    
    {:ok, connection_pid}
  end
  
  @doc """
  Simulates receiving a message from a WebSocket connection.
  
  ## Parameters
  
  * `test_pid` - The PID of the test process (usually `self()`)
  * `connection_pid` - The mock connection PID
  * `message` - The message to simulate receiving
  
  ## Returns
  
  * `:ok` - Message sent successfully
  """
  @spec simulate_message(pid(), pid(), map()) :: :ok
  def simulate_message(test_pid, connection_pid, message) do
    encoded_message = Jason.encode!(message)
    send(test_pid, {:websocket_message, connection_pid, encoded_message})
    :ok
  end
  
  @doc """
  Simulates a WebSocket connection error.
  
  ## Parameters
  
  * `test_pid` - The PID of the test process (usually `self()`)
  * `connection_pid` - The mock connection PID
  * `reason` - The error reason
  
  ## Returns
  
  * `:ok` - Error simulated successfully
  """
  @spec simulate_error(pid(), pid(), term()) :: :ok
  def simulate_error(test_pid, connection_pid, reason) do
    send(test_pid, {:websocket_error, connection_pid, reason})
    :ok
  end
  
  @doc """
  Simulates a WebSocket connection close.
  
  ## Parameters
  
  * `test_pid` - The PID of the test process (usually `self()`)
  * `connection_pid` - The mock connection PID
  
  ## Returns
  
  * `:ok` - Close simulated successfully
  """
  @spec simulate_close(pid(), pid()) :: :ok
  def simulate_close(test_pid, connection_pid) do
    send(test_pid, {:websocket_closed, connection_pid})
    :ok
  end
  
  # Private implementation
  
  @doc false
  # Loop that processes messages in the mock connection
  defp mock_connection_loop(test_pid, auto_respond, simulate_errors) do
    receive do
      {:send, message} ->
        if simulate_errors do
          # Simulate a network error
          Process.send_after(
            test_pid, 
            {:websocket_error, self(), :network_error}, 
            10
          )
        else
          # If auto-respond is enabled, simulate a response
          if auto_respond do
            response = generate_response(message)
            Process.send_after(
              test_pid, 
              {:websocket_message, self(), response}, 
              10
            )
          end
        end
        
        mock_connection_loop(test_pid, auto_respond, simulate_errors)
        
      {:close, _} ->
        # Simulate connection closed
        Process.send_after(
          test_pid, 
          {:websocket_closed, self()}, 
          10
        )
        
      other ->
        # Forward any other messages to the test process
        send(test_pid, {:mock_connection_received, other})
        mock_connection_loop(test_pid, auto_respond, simulate_errors)
    after
      60000 ->
        # Timeout after 1 minute of inactivity
        nil
    end
  end
  
  @doc false
  # Generate a response based on the request message
  defp generate_response(message) do
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
          value: "test_value_#{key}",
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
  end
end 