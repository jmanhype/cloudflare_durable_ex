defmodule CloudflareDurable.WebSocketTest do
  @moduledoc """
  Tests for CloudflareDurable WebSocket functionality.
  """
  
  use ExUnit.Case, async: true
  import Mock
  import ExUnit.CaptureLog
  
  alias CloudflareDurable.WebSocket
  alias CloudflareDurable.WebSocketTestHelper

  if Mix.env() == :test do
    # Import test-only modules
    import ExUnit.CaptureLog
  end
  
  @default_worker_url "https://example.com/worker"
  
  setup do
    # Set default worker URL for tests
    Application.put_env(:cloudflare_durable, :worker_url, @default_worker_url)
    
    # Setup Finch for HTTP requests (if not already started)
    unless Process.whereis(CloudflareDurable.Finch) do
      start_supervised!({Finch, name: CloudflareDurable.Finch})
    end
    
    # Start the WebSocket supervisor
    unless Process.whereis(CloudflareDurable.WebSocket.Supervisor) do
      start_supervised!(CloudflareDurable.WebSocket.Supervisor)
    end
    
    :ok
  end
  
  describe "connect/1" do
    test "connects successfully to a WebSocket endpoint" do
      with_mock CloudflareDurable.WebSocket.Supervisor, 
        [:passthrough], 
        [start_connection: fn _object_id, _opts -> {:ok, self()} end] do
        
        # Call the connect function
        result = CloudflareDurable.websocket_connect("test-object", [])
        
        # Verify the result
        assert {:ok, _connection} = result
        
        # Verify the mock was called
        assert_called CloudflareDurable.WebSocket.Supervisor.start_connection(:_, :_)
      end
    end
    
    test "handles connection errors" do
      error_reason = "connection refused"
      
      with_mock CloudflareDurable.WebSocket.Supervisor, 
        [:passthrough], 
        [start_connection: fn _object_id, _opts -> {:error, error_reason} end] do
        
        # Call the connect function
        result = CloudflareDurable.websocket_connect("test-object", [])
        
        # Verify the result
        assert {:error, ^error_reason} = result
        
        # Verify the mock was called
        assert_called CloudflareDurable.WebSocket.Supervisor.start_connection(:_, :_)
      end
    end
    
    test "logs connection details" do
      with_mock CloudflareDurable.WebSocket.Supervisor, 
        [:passthrough], 
        [start_connection: fn _object_id, _opts -> {:ok, self()} end] do
        
        # Capture logs during the connection
        log = capture_log(fn ->
          CloudflareDurable.websocket_connect("test-object", [])
        end)
        
        # Verify log contains connection information
        assert log =~ "Connecting to WebSocket"
        assert log =~ "test-object"
      end
    end
  end
  
  describe "websocket_send/2" do
    test "sends a message successfully" do
      # Create a mock connection
      connection = self()
      message = Jason.encode!(%{type: "test", data: "hello"})
      
      with_mock CloudflareDurable.WebSocket.Connection,
        [:passthrough],
        [send_message: fn _conn, _msg -> :ok end] do
        
        # Send a message
        result = CloudflareDurable.websocket_send(connection, message)
        
        # Verify the result
        assert result == :ok
        
        # Verify the mock was called
        assert_called CloudflareDurable.WebSocket.Connection.send_message(connection, message)
      end
    end
    
    test "handles send errors" do
      connection = self()
      message = Jason.encode!(%{type: "test"})
      
      with_mock CloudflareDurable.WebSocket.Connection, 
        [:passthrough], 
        [send_message: fn _conn, _msg -> {:error, :connection_closed} end] do
        
        # Send a message
        result = CloudflareDurable.websocket_send(connection, message)
        
        # Verify the result
        assert {:error, :connection_closed} = result
        
        # Verify the mock was called
        assert_called CloudflareDurable.WebSocket.Connection.send_message(connection, message)
      end
    end
    
    test "logs message sending" do
      # Create a mock connection
      connection = self()
      message = Jason.encode!(%{type: "test", data: "hello"})
      
      with_mock CloudflareDurable.WebSocket.Connection,
        [:passthrough],
        [send_message: fn _conn, _msg -> :ok end] do
        
        # Capture logs during the send
        log = capture_log(fn ->
          CloudflareDurable.websocket_send(connection, message)
        end)
        
        # Verify log contains message information
        assert log =~ "Sending WebSocket message"
      end
    end
  end
  
  describe "websocket_close/1" do
    test "closes a connection successfully" do
      # Create a mock connection
      connection = self()
      
      with_mock GenServer,
        [:passthrough],
        [stop: fn _pid, _reason -> :ok end] do
        
        # Close the connection
        result = CloudflareDurable.websocket_close(connection)
        
        # Verify the result
        assert result == :ok
        
        # Verify the mock was called
        assert_called GenServer.stop(connection, :normal)
      end
    end
    
    test "logs connection closing" do
      # Create a mock connection
      connection = self()
      
      with_mock GenServer,
        [:passthrough],
        [stop: fn _pid, _reason -> :ok end] do
        
        # Capture logs during the close
        log = capture_log(fn ->
          CloudflareDurable.websocket_close(connection)
        end)
        
        # Verify log contains connection information
        assert log =~ "Closing WebSocket connection"
      end
    end
  end
  
  describe "error handling" do
    test "handles network errors" do
      connection = self()
      
      with_mock CloudflareDurable.WebSocket.Connection,
        [:passthrough],
        [send_message: fn _conn, _msg -> {:error, :network_error} end] do
        
        # Send a message (which will trigger an error)
        result = CloudflareDurable.websocket_send(
          connection, 
          Jason.encode!(%{type: "test"})
        )
        
        # Verify we receive an error
        assert {:error, :network_error} = result
      end
    end
    
    test "handles malformed responses" do
      connection = self()
      
      with_mock CloudflareDurable.WebSocket.Connection,
        [:passthrough],
        [send_message: fn _conn, _msg -> {:error, :invalid_message} end] do
        
        # Capture logs during the send
        log = capture_log(fn ->
          result = CloudflareDurable.websocket_send(
            connection, 
            Jason.encode!(%{type: "echo", id: "123", data: "test"})
          )
          
          # Verify the result
          assert {:error, :invalid_message} = result
        end)
        
        # Verify log contains error information
        assert log =~ "Sending WebSocket message"
      end
    end
    
    test "handles unexpected message types" do
      connection = self()
      
      with_mock CloudflareDurable.WebSocket.Connection,
        [:passthrough],
        [send_message: fn _conn, _msg -> :ok end] do
        
        # Send a message with an unknown type
        result = CloudflareDurable.websocket_send(
          connection, 
          Jason.encode!(%{type: "unknown_type", data: "test"})
        )
        
        # Verify we can still send messages
        assert result == :ok
      end
    end
    
    test "handles connection drops" do
      connection = self()
      
      with_mock GenServer,
        [:passthrough],
        [stop: fn _pid, _reason -> :ok end] do
        
        # Close the connection
        result = CloudflareDurable.websocket_close(connection)
        
        # Verify the result
        assert result == :ok
      end
    end
  end
  
  describe "complex scenarios" do
    test "can handle multiple messages in sequence" do
      connection = self()
      
      with_mock CloudflareDurable.WebSocket.Connection,
        [:passthrough],
        [send_message: fn _conn, _msg -> :ok end] do
        
        # Send a series of messages
        for i <- 1..5 do
          message = Jason.encode!(%{type: "echo", id: "msg_#{i}", data: "test_#{i}"})
          result = CloudflareDurable.websocket_send(connection, message)
          
          # Verify the result
          assert result == :ok
        end
      end
    end
    
    test "can recover from errors" do
      connection = self()
      
      # First message succeeds
      with_mock CloudflareDurable.WebSocket.Connection,
        [:passthrough],
        [send_message: fn _conn, _msg -> :ok end] do
        
        # Send a message
        message1 = Jason.encode!(%{type: "echo", id: "1", data: "before_error"})
        result1 = CloudflareDurable.websocket_send(connection, message1)
        
        # Verify the result
        assert result1 == :ok
      end
      
      # Second message fails
      with_mock CloudflareDurable.WebSocket.Connection,
        [:passthrough],
        [send_message: fn _conn, _msg -> {:error, :temporary_failure} end] do
        
        # Send a message that will fail
        message2 = Jason.encode!(%{type: "echo", id: "2", data: "error"})
        result2 = CloudflareDurable.websocket_send(connection, message2)
        
        # Verify the result
        assert {:error, :temporary_failure} = result2
      end
      
      # Third message succeeds again
      with_mock CloudflareDurable.WebSocket.Connection,
        [:passthrough],
        [send_message: fn _conn, _msg -> :ok end] do
        
        # Send a message after the error
        message3 = Jason.encode!(%{type: "echo", id: "3", data: "after_error"})
        result3 = CloudflareDurable.websocket_send(connection, message3)
        
        # Verify the result
        assert result3 == :ok
      end
    end
  end
end 