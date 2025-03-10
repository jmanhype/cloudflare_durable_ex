defmodule CloudflareDurable.WebSocketTest do
  @moduledoc """
  Tests for CloudflareDurable WebSocket functionality.
  """
  
  use ExUnit.Case, async: true
  import Mock
  
  alias CloudflareDurable.WebSocket
  alias CloudflareDurable.WebSocketTestHelper

  if Mix.env() == :test do
    # Import test-only modules
    import ExUnit.CaptureLog
  end
  
  describe "connect/1" do
    test "connects successfully to a WebSocket endpoint" do
      with_mock CloudflareDurable.WebSocket, 
        [:passthrough], 
        [connect: fn _url -> {:ok, self()} end] do
        
        # Call the connect function
        result = CloudflareDurable.websocket_connect("test-object", [])
        
        # Verify the result
        assert {:ok, _connection} = result
        
        # Verify the mock was called
        assert_called WebSocket.connect(:_)
      end
    end
    
    test "handles connection errors" do
      error_reason = "connection refused"
      
      with_mock CloudflareDurable.WebSocket, 
        [:passthrough], 
        [connect: fn _url -> {:error, error_reason} end] do
        
        # Call the connect function
        result = CloudflareDurable.websocket_connect("test-object", [])
        
        # Verify the result
        assert {:error, ^error_reason} = result
        
        # Verify the mock was called
        assert_called WebSocket.connect(:_)
      end
    end
    
    test "logs connection details" do
      with_mock CloudflareDurable.WebSocket, 
        [:passthrough], 
        [connect: fn _url -> {:ok, self()} end] do
        
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
      {:ok, connection} = WebSocketTestHelper.create_mock_connection(self())
      message = Jason.encode!(%{type: "test", data: "hello"})
      
      # Send a message
      result = CloudflareDurable.websocket_send(connection, message)
      
      # Verify the result
      assert result == :ok
      
      # Verify we receive a response
      assert_receive {:websocket_message, ^connection, _response}, 100
    end
    
    test "handles send errors" do
      with_mock CloudflareDurable.WebSocket, 
        [:passthrough], 
        [send: fn _conn, _msg -> {:error, :connection_closed} end] do
        
        # Send a message
        result = CloudflareDurable.websocket_send(
          self(), 
          Jason.encode!(%{type: "test"})
        )
        
        # Verify the result
        assert {:error, :connection_closed} = result
      end
    end
    
    test "logs message sending" do
      # Create a mock connection
      {:ok, connection} = WebSocketTestHelper.create_mock_connection(self())
      message = Jason.encode!(%{type: "test", data: "hello"})
      
      # Capture logs during message sending
      log = capture_log(fn ->
        CloudflareDurable.websocket_send(connection, message)
      end)
      
      # Verify log contains message information
      assert log =~ "Sending WebSocket message"
      assert log =~ "test"
    end
  end
  
  describe "websocket_close/1" do
    test "closes a connection successfully" do
      # Create a mock connection
      {:ok, connection} = WebSocketTestHelper.create_mock_connection(self())
      
      # Close the connection
      result = CloudflareDurable.websocket_close(connection)
      
      # Verify the result
      assert result == :ok
      
      # Verify we receive a close notification
      assert_receive {:websocket_closed, ^connection}, 100
    end
    
    test "logs connection closing" do
      # Create a mock connection
      {:ok, connection} = WebSocketTestHelper.create_mock_connection(self())
      
      # Capture logs during connection closing
      log = capture_log(fn ->
        CloudflareDurable.websocket_close(connection)
      end)
      
      # Verify log contains closing information
      assert log =~ "Closing WebSocket connection"
    end
  end
  
  describe "error handling" do
    test "handles network errors" do
      # Create a mock connection that simulates errors
      {:ok, connection} = WebSocketTestHelper.create_mock_connection(
        self(), 
        simulate_errors: true
      )
      
      # Send a message (which will trigger an error)
      CloudflareDurable.websocket_send(
        connection, 
        Jason.encode!(%{type: "test"})
      )
      
      # Verify we receive an error notification
      assert_receive {:websocket_error, ^connection, :network_error}, 100
    end
    
    test "handles malformed responses" do
      # Create a mock connection
      {:ok, connection} = WebSocketTestHelper.create_mock_connection(self(), auto_respond: false)
      
      # Simulate receiving a malformed message
      WebSocketTestHelper.simulate_message(self(), connection, %{
        type: "invalid_format",
        data: %{nested: "value"}
      })
      
      # Send a message that expects a specific response format
      log = capture_log(fn ->
        CloudflareDurable.websocket_send(
          connection, 
          Jason.encode!(%{type: "echo", id: "123", data: "test"})
        )
        
        # Simulate response with invalid format
        send(self(), {:websocket_message, connection, "{\"invalid\":\"format\"}"})
        
        # Wait for log to capture
        Process.sleep(50)
      end)
      
      # Verify log contains error information
      assert log =~ "Received WebSocket message"
    end
    
    test "handles unexpected message types" do
      # Create a mock connection
      {:ok, connection} = WebSocketTestHelper.create_mock_connection(self())
      
      # Simulate an unexpected message type
      WebSocketTestHelper.simulate_message(self(), connection, %{
        type: "unknown_type",
        data: "test"
      })
      
      # Verify we can still send messages after receiving an unknown type
      result = CloudflareDurable.websocket_send(
        connection, 
        Jason.encode!(%{type: "echo", id: "123", data: "after_unknown"})
      )
      
      assert result == :ok
    end
    
    test "handles connection drops" do
      # Create a mock connection
      {:ok, connection} = WebSocketTestHelper.create_mock_connection(self())
      
      # Simulate a connection close
      WebSocketTestHelper.simulate_close(self(), connection)
      
      # Verify connection is closed properly
      assert_receive {:websocket_closed, ^connection}
    end
  end
  
  describe "complex scenarios" do
    test "can handle multiple messages in sequence" do
      # Create a mock connection
      {:ok, connection} = WebSocketTestHelper.create_mock_connection(self())
      
      # Send a series of messages
      for i <- 1..5 do
        result = CloudflareDurable.websocket_send(
          connection, 
          Jason.encode!(%{type: "echo", id: "msg_#{i}", data: "test_#{i}"})
        )
        
        assert result == :ok
        
        # Verify we receive a response for each message
        assert_receive {:websocket_message, ^connection, response}, 100
        
        # Verify the response contains the expected data
        parsed = Jason.decode!(response)
        assert parsed["type"] == "echo_response"
        assert parsed["id"] == "msg_#{i}"
        assert parsed["data"] == "test_#{i}"
      end
    end
    
    test "can recover from errors" do
      # Create a mock connection
      {:ok, connection} = WebSocketTestHelper.create_mock_connection(self())
      
      # Send a message
      CloudflareDurable.websocket_send(
        connection, 
        Jason.encode!(%{type: "echo", id: "1", data: "before_error"})
      )
      
      # Verify we receive a response
      assert_receive {:websocket_message, ^connection, _response}, 100
      
      # Simulate an error
      WebSocketTestHelper.simulate_error(self(), connection, :temporary_failure)
      
      # Send another message after the error
      result = CloudflareDurable.websocket_send(
        connection, 
        Jason.encode!(%{type: "echo", id: "2", data: "after_error"})
      )
      
      # Verify we can still send messages
      assert result == :ok
      
      # Verify we receive a response for the second message
      assert_receive {:websocket_message, ^connection, response}, 100
      parsed = Jason.decode!(response)
      assert parsed["type"] == "echo_response"
      assert parsed["id"] == "2"
      assert parsed["data"] == "after_error"
    end
  end
end 