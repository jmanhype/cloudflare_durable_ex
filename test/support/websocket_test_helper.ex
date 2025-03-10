defmodule CloudflareDurable.WebSocketTestHelper do
  @moduledoc """
  Helper functions for testing WebSocket connections in CloudflareDurable.
  
  This module provides utilities for mocking WebSocket connections and
  simulating WebSocket events in tests.
  """
  
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
  defp mock_connection_loop(test_pid, auto_respond, simulate_errors) do
    # Register this process with a unique name to avoid conflicts
    Process.register(self(), :"CloudflareDurable.WebSocketTestMock.#{:erlang.unique_integer([:positive])}")
    
    if simulate_errors do
      # Simulate a connection error
      Process.send_after(
        test_pid, 
        {:websocket_error, self(), "connection refused"}, 
        10
      )
    end
    
    # Enter the loop
    mock_connection_receive_loop(test_pid, auto_respond)
  end
  
  defp mock_connection_receive_loop(test_pid, auto_respond) do
    receive do
      {:send_message, message} ->
        # Handle the message
        if auto_respond do
          # Extract the type from the JSON message
          case Jason.decode(message) do
            {:ok, %{"type" => type} = decoded} ->
              # Determine the response based on the message type
              response = case type do
                "echo" -> 
                  data = Map.get(decoded, "data", "")
                  Jason.encode!(%{type: "echo_response", data: data})
                
                "get" -> 
                  key = Map.get(decoded, "key", "")
                  Jason.encode!(%{type: "get_response", key: key, value: "value_#{key}"})
                
                "set" -> 
                  key = Map.get(decoded, "key", "")
                  value = Map.get(decoded, "value", "")
                  Jason.encode!(%{type: "set_response", key: key, value: value})
                
                "error" -> 
                  # Simulate an error
                  Process.send_after(
                    test_pid, 
                    {:websocket_error, self(), "error requested"}, 
                    10
                  )
                  nil
                
                "close" -> 
                  # Simulate a close
                  Process.send_after(
                    test_pid, 
                    {:websocket_closed, self()}, 
                    10
                  )
                  nil
                
                _ -> 
                  Jason.encode!(%{type: "unknown_command"})
              end
              
              # Send the response if it's not nil
              if response do
                Process.send_after(
                  test_pid, 
                  {:websocket_message, self(), response}, 
                  10
                )
              end
            
            {:error, _} ->
              # Invalid JSON, send an error
              Process.send_after(
                test_pid, 
                {:websocket_error, self(), "invalid JSON"}, 
                10
              )
          end
        end
        
        # Send a reply to the GenServer call
        send(test_pid, {:mock_send_reply, :ok})
      
      {:subscribe, subscriber_pid} ->
        # Send a reply to the GenServer call
        send(test_pid, {:mock_subscribe_reply, :ok})
      
      {:unsubscribe, subscriber_pid} ->
        # Send a reply to the GenServer call
        send(test_pid, {:mock_unsubscribe_reply, :ok})
      
      :status ->
        # Send a reply to the GenServer call
        send(test_pid, {:mock_status_reply, :connected})
      
      {:system, from, request} ->
        # System messages for GenServer.stop
        case request do
          :get_state ->
            send(from, {:state, %{test_pid: test_pid}})
          
          {:terminate, _reason, _a} ->
            # Handle termination
            send(test_pid, {:mock_terminated})
            exit(:normal)
        end
      
      _other ->
        # Ignore any other messages
        :ok
    end
    
    # Continue the loop
    mock_connection_receive_loop(test_pid, auto_respond)
  end
end 