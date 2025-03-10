#!/usr/bin/env elixir

# Make sure the package is in the code path
Code.prepend_path("_build/dev/lib/cloudflare_durable/ebin")
Code.prepend_path("_build/dev/lib/jason/ebin")
Code.prepend_path("_build/dev/lib/finch/ebin")
Code.prepend_path("_build/dev/lib/mint_web_socket/ebin")
Code.prepend_path("_build/dev/lib/telemetry/ebin")

defmodule WebSocketExample do
  @moduledoc """
  Example showing how to use CloudflareDurable WebSocket connections.
  
  This example demonstrates:
  1. Establishing a WebSocket connection to a Durable Object
  2. Sending and receiving messages over WebSocket
  3. Handling WebSocket events (connected, disconnected, error)
  4. Proper cleanup and error handling
  
  ## Usage
  
  Set the CLOUDFLARE_WORKER_URL environment variable to your Cloudflare Worker URL
  and run this script:
  
  ```
  CLOUDFLARE_WORKER_URL=https://your-worker.your-account.workers.dev elixir examples/websocket_connection.exs
  ```
  
  ## Durable Object Implementation
  
  This example assumes your Durable Object implements a WebSocket endpoint that:
  - Accepts connection requests
  - Handles "echo" message type by reflecting the message back
  - Handles "get" message type to retrieve values
  - Handles "set" message type to store values
  """
  
  require Logger
  
  @doc """
  Runs the WebSocket example.
  
  This function demonstrates a complete WebSocket interaction:
  1. Establish a WebSocket connection
  2. Send echo, get, and set messages
  3. Process responses
  4. Clean up resources
  
  Each step includes proper error handling and logging.
  
  ## Returns
  
  * `:ok` - Example completed successfully (regardless of any errors that occurred)
  """
  @spec run() :: :ok
  def run do
    # Configure the worker URL
    worker_url = get_worker_url()
    Application.put_env(:cloudflare_durable, :worker_url, worker_url)
    
    # Generate a unique ID for the Durable Object
    object_id = generate_object_id()
    IO.puts("Using object ID: #{object_id}")
    
    # Initialize the Durable Object
    case initialize_object(object_id) do
      {:ok, _} ->
        # Create a WebSocket connection
        case create_websocket_connection(object_id) do
          {:ok, connection} ->
            # Send messages and handle responses
            :ok = send_websocket_messages(connection)
            
            # Sleep briefly to ensure we have time to process responses
            Process.sleep(3000)
            
            # Close the connection
            :ok = close_websocket_connection(connection)
            
          {:error, reason} ->
            IO.puts("Failed to create WebSocket connection: #{inspect(reason)}")
        end
        
      {:error, reason} ->
        IO.puts("Failed to initialize object: #{inspect(reason)}")
    end
    
    IO.puts("\nExample completed.")
    :ok
  end
  
  @doc """
  Gets the Cloudflare Worker URL from environment variables.
  
  ## Returns
  
  * `String.t()` - The Cloudflare Worker URL
  
  ## Raises
  
  * `RuntimeError` - If the CLOUDFLARE_WORKER_URL environment variable is not set
  """
  @spec get_worker_url() :: String.t()
  defp get_worker_url do
    System.get_env("CLOUDFLARE_WORKER_URL") || 
      raise "Please set the CLOUDFLARE_WORKER_URL environment variable"
  end
  
  @doc """
  Generates a unique ID for the Durable Object based on the current time.
  
  ## Returns
  
  * `String.t()` - A unique object ID
  """
  @spec generate_object_id() :: String.t()
  defp generate_object_id do
    "websocket-#{:os.system_time(:millisecond)}"
  end
  
  @doc """
  Initializes a Durable Object with empty state.
  
  ## Parameters
  
  * `object_id` - The ID of the Durable Object
  
  ## Returns
  
  * `{:ok, map()}` - Successfully initialized Durable Object
  * `{:error, term()}` - Failed to initialize Durable Object
  """
  @spec initialize_object(String.t()) :: {:ok, map()} | {:error, term()}
  defp initialize_object(object_id) do
    case CloudflareDurable.initialize(object_id, %{messages: []}) do
      {:ok, response} ->
        IO.puts("Initialized object: #{inspect(response)}")
        {:ok, response}
        
      {:error, _} = error ->
        error
    end
  end
  
  @doc """
  Creates a WebSocket connection to a Durable Object.
  
  ## Parameters
  
  * `object_id` - The ID of the Durable Object
  
  ## Returns
  
  * `{:ok, pid()}` - Successfully created WebSocket connection
  * `{:error, term()}` - Failed to create WebSocket connection
  """
  @spec create_websocket_connection(String.t()) :: {:ok, pid()} | {:error, term()}
  defp create_websocket_connection(object_id) do
    case CloudflareDurable.websocket_connect(object_id, [subscriber: self()]) do
      {:ok, connection} ->
        IO.puts("WebSocket connection established")
        
        # Set up a message handler
        setup_message_handler()
        
        {:ok, connection}
        
      {:error, _} = error ->
        error
    end
  end
  
  @doc """
  Sets up a process to handle incoming WebSocket messages.
  
  This function starts a receive loop in the current process to handle
  messages from the WebSocket connection.
  
  ## Returns
  
  * `:ok` - Message handler set up successfully
  """
  @spec setup_message_handler() :: :ok
  defp setup_message_handler do
    spawn(fn -> message_loop() end)
    :ok
  end
  
  @doc """
  Infinite loop that processes WebSocket messages.
  
  This function continuously receives messages from the WebSocket connection
  and handles them appropriately.
  """
  @spec message_loop() :: no_return()
  defp message_loop do
    receive do
      {:websocket_message, _connection, message} ->
        handle_websocket_message(message)
        message_loop()
        
      {:websocket_closed, _connection} ->
        IO.puts("WebSocket connection closed")
        
      {:websocket_error, _connection, reason} ->
        IO.puts("WebSocket error: #{inspect(reason)}")
        message_loop()
        
      other ->
        IO.puts("Received unexpected message: #{inspect(other)}")
        message_loop()
    after
      10000 ->
        IO.puts("Message handler timed out waiting for messages")
    end
  end
  
  @doc """
  Handles an incoming WebSocket message.
  
  ## Parameters
  
  * `message` - The message received from the WebSocket connection
  
  ## Returns
  
  * `:ok` - Message handled successfully
  """
  @spec handle_websocket_message(String.t()) :: :ok
  defp handle_websocket_message(message) do
    case Jason.decode(message) do
      {:ok, decoded} ->
        IO.puts("Received WebSocket message: #{inspect(decoded)}")
        :ok
        
      {:error, reason} ->
        IO.puts("Error decoding WebSocket message: #{inspect(reason)}")
        :ok
    end
  end
  
  @doc """
  Sends a series of test messages over the WebSocket connection.
  
  ## Parameters
  
  * `connection` - The WebSocket connection PID
  
  ## Returns
  
  * `:ok` - Messages sent successfully
  """
  @spec send_websocket_messages(pid()) :: :ok
  defp send_websocket_messages(connection) do
    # Send echo message
    send_echo_message(connection, "Hello, Durable Object!")
    Process.sleep(500)
    
    # Send set message
    send_set_message(connection, "greeting", "Hello from Elixir!")
    Process.sleep(500)
    
    # Send get message
    send_get_message(connection, "greeting")
    Process.sleep(500)
    
    :ok
  end
  
  @doc """
  Sends an echo message over the WebSocket connection.
  
  ## Parameters
  
  * `connection` - The WebSocket connection PID
  * `data` - The data to echo
  
  ## Returns
  
  * `:ok` - Message sent successfully
  * `{:error, term()}` - Failed to send message
  """
  @spec send_echo_message(pid(), String.t()) :: :ok | {:error, term()}
  defp send_echo_message(connection, data) do
    message = Jason.encode!(%{
      type: "echo",
      id: random_id(),
      data: data
    })
    
    IO.puts("Sending echo message: #{message}")
    CloudflareDurable.websocket_send(connection, message)
  end
  
  @doc """
  Sends a set message over the WebSocket connection.
  
  ## Parameters
  
  * `connection` - The WebSocket connection PID
  * `key` - The key to set
  * `value` - The value to set
  
  ## Returns
  
  * `:ok` - Message sent successfully
  * `{:error, term()}` - Failed to send message
  """
  @spec send_set_message(pid(), String.t(), String.t()) :: :ok | {:error, term()}
  defp send_set_message(connection, key, value) do
    message = Jason.encode!(%{
      type: "set",
      id: random_id(),
      key: key,
      value: value
    })
    
    IO.puts("Sending set message: #{message}")
    CloudflareDurable.websocket_send(connection, message)
  end
  
  @doc """
  Sends a get message over the WebSocket connection.
  
  ## Parameters
  
  * `connection` - The WebSocket connection PID
  * `key` - The key to get
  
  ## Returns
  
  * `:ok` - Message sent successfully
  * `{:error, term()}` - Failed to send message
  """
  @spec send_get_message(pid(), String.t()) :: :ok | {:error, term()}
  defp send_get_message(connection, key) do
    message = Jason.encode!(%{
      type: "get",
      id: random_id(),
      key: key
    })
    
    IO.puts("Sending get message: #{message}")
    CloudflareDurable.websocket_send(connection, message)
  end
  
  @doc """
  Generates a random ID for message correlation.
  
  ## Returns
  
  * `String.t()` - A random ID
  """
  @spec random_id() :: String.t()
  defp random_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  @doc """
  Closes a WebSocket connection.
  
  ## Parameters
  
  * `connection` - The WebSocket connection PID
  
  ## Returns
  
  * `:ok` - Connection closed successfully
  """
  @spec close_websocket_connection(pid()) :: :ok
  defp close_websocket_connection(connection) do
    IO.puts("Closing WebSocket connection")
    CloudflareDurable.websocket_close(connection)
  end
end

WebSocketExample.run() 