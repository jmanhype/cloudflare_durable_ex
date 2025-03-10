defmodule CloudflareDurable.Benchmark.WebSocket do
  @moduledoc """
  Benchmarks for WebSocket operations with Cloudflare Durable Objects.
  
  This module provides benchmarks for measuring the performance of WebSocket
  connections to Cloudflare Durable Objects, including connection establishment,
  message sending, and concurrent connections.
  """
  
  require Logger
  alias CloudflareDurable.Benchmark.Utils
  alias CloudflareDurable.WebSocket.Connection

  @doc """
  Runs the WebSocket benchmark suite.
  
  ## Parameters
  
    * `output_path` - Optional path to save benchmark results to
    * `save_results` - Whether to save results to a timestamped file
    * `compare_file` - Optional path to a previous benchmark result to compare against
  
  ## Returns
  
    * `:ok` - The benchmark completed successfully
  """
  @spec run(String.t() | nil, boolean(), String.t() | nil) :: :ok
  def run(output_path, save_results, compare_file) do
    # Load configuration or use defaults
    config = load_config()
    
    # Print benchmark information
    IO.puts("\n=== WebSocket Benchmarks ===\n")
    IO.puts("Worker URL: #{config.worker_url}")
    IO.puts("Concurrency: #{config.concurrency}")
    IO.puts("Duration: #{config.duration} seconds\n")
    
    # Run the benchmarks
    benchmarks = %{
      "websocket_connect" => fn -> benchmark_websocket_connect(config) end,
      "websocket_send_small_message" => fn -> benchmark_websocket_send(config, :small) end,
      "websocket_send_medium_message" => fn -> benchmark_websocket_send(config, :medium) end,
      "websocket_send_large_message" => fn -> benchmark_websocket_send(config, :large) end,
      "websocket_roundtrip" => fn -> benchmark_websocket_roundtrip(config) end
    }
    
    # Execute the benchmarks
    Benchee.run(
      benchmarks,
      time: config.duration,
      memory_time: config.duration,
      warmup: 2,
      parallel: config.concurrency,
      formatters: [
        Benchee.Formatters.Console,
        {Benchee.Formatters.HTML, file: output_path && "#{output_path}/websocket.html"}
      ],
      print: [fast_warning: false],
      save: save_results && [path: "benchmarks/results/websocket_#{Utils.timestamp()}.benchee"],
      load: compare_file && compare_file
    )
    
    :ok
  end
  
  # Helper functions
  
  @doc false
  defp load_config do
    %{
      worker_url: System.get_env("BENCHMARK_WORKER_URL", "http://localhost:8787"),
      concurrency: String.to_integer(System.get_env("BENCHMARK_CONCURRENCY", "4")),
      duration: String.to_integer(System.get_env("BENCHMARK_DURATION", "5"))
    }
  end
  
  @doc false
  defp benchmark_websocket_connect(config) do
    # Generate a unique object ID for this benchmark iteration
    object_id = Utils.random_id()
    
    # First, initialize the object
    {:ok, _} = CloudflareDurable.initialize(
      object_id,
      %{initialized_at: DateTime.utc_now(), value: 0},
      worker_url: config.worker_url
    )
    
    # Open a WebSocket connection
    result = CloudflareDurable.open_websocket(
      object_id,
      worker_url: config.worker_url,
      auto_reconnect: false
    )
    
    # Clean up the connection if successful
    case result do
      {:ok, pid} -> Process.exit(pid, :normal)
      _ -> nil
    end
    
    result
  end
  
  @doc false
  defp benchmark_websocket_send(config, message_size) do
    # Generate a unique object ID for this benchmark iteration
    object_id = Utils.random_id()
    
    # First, initialize the object
    {:ok, _} = CloudflareDurable.initialize(
      object_id,
      %{initialized_at: DateTime.utc_now(), value: 0},
      worker_url: config.worker_url
    )
    
    # Open a WebSocket connection
    {:ok, ws} = CloudflareDurable.open_websocket(
      object_id,
      worker_url: config.worker_url,
      auto_reconnect: false
    )
    
    # Wait for the connection to be established
    :timer.sleep(200)
    
    # Generate a message based on the requested size
    message = case message_size do
      :small -> Jason.encode!(%{type: "echo", data: "Hello"})
      :medium -> Jason.encode!(%{type: "echo", data: Utils.random_string(1000)})
      :large -> Jason.encode!(%{type: "echo", data: Utils.random_string(10000)})
    end
    
    # Send the message
    result = Connection.send_message(ws, message)
    
    # Clean up the connection
    Process.exit(ws, :normal)
    
    result
  end
  
  @doc false
  defp benchmark_websocket_roundtrip(config) do
    # Generate a unique object ID for this benchmark iteration
    object_id = Utils.random_id()
    
    # First, initialize the object
    {:ok, _} = CloudflareDurable.initialize(
      object_id,
      %{initialized_at: DateTime.utc_now(), value: 0},
      worker_url: config.worker_url
    )
    
    # Create a unique message ID for this round trip
    message_id = Utils.random_id()
    
    # Open a WebSocket connection with this process as a subscriber
    {:ok, ws} = CloudflareDurable.open_websocket(
      object_id,
      worker_url: config.worker_url,
      auto_reconnect: false
    )
    
    # Subscribe to messages
    :ok = Connection.subscribe(ws)
    
    # Wait for the connection to be established
    :timer.sleep(200)
    
    # Send a message with the message ID
    :ok = Connection.send_message(ws, Jason.encode!(%{type: "echo", id: message_id, data: "ping"}))
    
    # Wait for the response with matching message ID
    receive do
      {:websocket_message, response} ->
        case Jason.decode(response) do
          {:ok, %{"id" => ^message_id}} -> 
            # Successfully received the response with the matching ID
            Process.exit(ws, :normal)
            :ok
          _ ->
            # Not the message we're looking for, keep waiting
            benchmark_websocket_roundtrip(config)
        end
    after
      2000 ->
        # Timeout waiting for response
        Process.exit(ws, :normal)
        {:error, :timeout}
    end
  end
end 