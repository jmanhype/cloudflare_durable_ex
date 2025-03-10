defmodule CloudflareDurable.Benchmarks.WebSocket do
  @moduledoc """
  Benchmarks for WebSocket connections to Cloudflare Workers.
  
  These benchmarks test the performance of various WebSocket operations
  when interacting with Cloudflare Durable Objects.
  """
  
  alias CloudflareDurable.WebSocket
  
  @doc """
  Run all WebSocket benchmarks.
  """
  @spec run(keyword()) :: :ok
  def run(opts \\ []) do
    # Get configuration from environment or defaults
    worker_url = System.get_env("BENCHMARK_WORKER_URL", "http://localhost:8787")
    base_url = String.replace(worker_url, ~r(^http), "ws")
    websocket_url = "#{base_url}/name/benchmark"
    duration = String.to_integer(System.get_env("BENCHMARK_DURATION", "5"))
    
    concurrency = String.to_integer(System.get_env("BENCHMARK_CONCURRENCY", "4"))
    
    # Initialize the durable object with test data
    http_opts = [
      pool_timeout: 50_000,
      receive_timeout: 50_000
    ]
    initialize_benchmark_object(worker_url, http_opts)
    
    # Create WebSocket connections to be used in benchmarks
    connections = 1..concurrency |> Enum.map(fn _ -> establish_connection(websocket_url) end)
    
    # Prepare the benchmarks
    benchmarks = %{
      "WebSocket echo (small message)" => fn -> 
        connection = Enum.random(connections)
        benchmark_echo(connection, %{message: "Hello, World!", timestamp: DateTime.utc_now()})
      end,
      "WebSocket echo (medium message)" => fn ->
        connection = Enum.random(connections)
        data = %{
          message: "This is a medium sized message with some nested data structures.",
          items: Enum.to_list(1..20),
          details: %{
            source: "benchmark",
            category: "websocket",
            tags: ["performance", "test", "websocket"]
          },
          timestamp: DateTime.utc_now()
        }
        benchmark_echo(connection, data)
      end,
      "WebSocket get (key lookup)" => fn ->
        connection = Enum.random(connections)
        benchmark_get(connection, "test_key")
      end,
      "WebSocket set (key update)" => fn ->
        connection = Enum.random(connections)
        benchmark_set(connection, "ws_random_key", :crypto.strong_rand_bytes(10) |> Base.encode64())
      end
    }
    
    # Run the benchmarks
    Benchee.run(
      benchmarks,
      time: duration,
      memory_time: 2,
      warmup: 2,
      formatters: get_formatters(opts),
      print: [fast_warning: false]
    )
    
    # Close all connections
    Enum.each(connections, &close_connection/1)
    
    :ok
  end
  
  # Get appropriate formatters based on options
  defp get_formatters(opts) do
    formatters = [Benchee.Formatters.Console]
    
    formatters =
      if html_output = opts[:output] || opts[:o] do
        dir = if is_binary(html_output), do: html_output, else: "benchmarks/results"
        File.mkdir_p!(dir)
        [Benchee.Formatters.HTML, formatters]
      else
        formatters
      end
      
    formatters =
      if opts[:save] || opts[:s] do
        results_dir = "benchmarks/results"
        File.mkdir_p!(results_dir)
        date_time = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(~r/[^\d]/, "")
        file_path = Path.join(results_dir, "websocket_results_#{date_time}.benchee")
        [{Benchee.Formatters.Console, extended_statistics: true}, {Benchee.Formatters.TaggedSave, path: file_path} | formatters]
      else
        formatters
      end
    
    List.flatten(formatters)
  end
  
  # Initialize the benchmark object with test data
  defp initialize_benchmark_object(worker_url, http_opts) do
    url = "#{worker_url}/name/benchmark/initialize"
    
    initial_data = %{
      "counter" => 0,
      "test_key" => "test_value",
      "number" => 42,
      "list" => [1, 2, 3],
      "map" => %{"key" => "value"}
    }
    
    case CloudflareDurable.HTTP.request(
      :post,
      url,
      Jason.encode!(initial_data),
      [{"content-type", "application/json"}],
      http_opts
    ) do
      {:ok, status, _headers, _body} when status in 200..299 ->
        :ok
      {:ok, status, _headers, body} ->
        IO.puts("Warning: Initialization request returned status #{status}: #{body}")
        :ok
      {:error, reason} ->
        IO.puts("Warning: Failed to initialize benchmark object: #{inspect(reason)}")
        :ok
    end
  end
  
  # Establish a WebSocket connection
  defp establish_connection(url) do
    {:ok, conn} = WebSocket.connect(url)
    
    # Wait for the initial connection message
    receive do
      {:websocket_message, ^conn, message} ->
        case Jason.decode(message) do
          {:ok, %{"type" => "connected"}} -> :ok
          _ -> :error
        end
      after 5000 ->
        :timeout
    end
    
    conn
  end
  
  # Close a WebSocket connection
  defp close_connection(conn) do
    WebSocket.close(conn)
  end
  
  # Benchmark echo operation
  defp benchmark_echo(conn, data) do
    message_id = System.monotonic_time()
    message = %{
      type: "echo",
      id: message_id,
      data: data
    }
    
    WebSocket.send(conn, Jason.encode!(message))
    
    receive do
      {:websocket_message, ^conn, response} ->
        case Jason.decode(response) do
          {:ok, %{"type" => "echo_response", "id" => ^message_id}} -> :ok
          _ -> :error
        end
      after 5000 ->
        :timeout
    end
  end
  
  # Benchmark get operation
  defp benchmark_get(conn, key) do
    message_id = System.monotonic_time()
    message = %{
      type: "get",
      id: message_id,
      key: key
    }
    
    WebSocket.send(conn, Jason.encode!(message))
    
    receive do
      {:websocket_message, ^conn, response} ->
        case Jason.decode(response) do
          {:ok, %{"type" => "get_response", "id" => ^message_id}} -> :ok
          _ -> :error
        end
      after 5000 ->
        :timeout
    end
  end
  
  # Benchmark set operation
  defp benchmark_set(conn, key, value) do
    message_id = System.monotonic_time()
    message = %{
      type: "set",
      id: message_id,
      key: key,
      value: value
    }
    
    WebSocket.send(conn, Jason.encode!(message))
    
    receive do
      {:websocket_message, ^conn, response} ->
        case Jason.decode(response) do
          {:ok, %{"type" => "set_response", "id" => ^message_id}} -> :ok
          _ -> :error
        end
      after 5000 ->
        :timeout
    end
  end
end

# Run the benchmarks if this file is executed directly
if System.get_env("BENCHEE_RUN") == "true" do
  # Parse command line arguments
  {opts, _args} = 
    System.argv()
    |> OptionParser.parse!(
      aliases: [o: :output, s: :save, c: :compare],
      switches: [output: :string, save: :boolean, compare: :string]
    )
    
  CloudflareDurable.Benchmarks.WebSocket.run(opts)
end 