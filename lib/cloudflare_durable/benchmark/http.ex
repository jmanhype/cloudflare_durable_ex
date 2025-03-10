defmodule CloudflareDurable.Benchmark.Http do
  @moduledoc """
  Benchmarks for HTTP requests to Cloudflare Durable Objects.
  
  This module provides benchmarks for measuring the performance of HTTP requests
  to Cloudflare Durable Objects, including initialization, method calls, and state operations.
  """
  
  require Logger
  alias CloudflareDurable.Benchmark.Utils

  @doc """
  Runs the HTTP benchmark suite.
  
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
    IO.puts("\n=== HTTP Request Benchmarks ===\n")
    IO.puts("Worker URL: #{config.worker_url}")
    IO.puts("Concurrency: #{config.concurrency}")
    IO.puts("Duration: #{config.duration} seconds\n")
    
    # Run the benchmarks
    benchmarks = %{
      "initialize_object" => fn -> benchmark_initialize(config) end,
      "call_method_small_payload" => fn -> benchmark_call_method(config, :small) end,
      "call_method_medium_payload" => fn -> benchmark_call_method(config, :medium) end,
      "call_method_large_payload" => fn -> benchmark_call_method(config, :large) end,
      "get_state" => fn -> benchmark_get_state(config) end,
      "update_state" => fn -> benchmark_update_state(config) end,
      "delete_state" => fn -> benchmark_delete_state(config) end
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
        {Benchee.Formatters.HTML, file: output_path && "#{output_path}/http.html"}
      ],
      print: [fast_warning: false],
      save: save_results && [path: "benchmarks/results/http_#{Utils.timestamp()}.benchee"],
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
  defp benchmark_initialize(config) do
    # Generate a unique object ID for this benchmark iteration
    object_id = Utils.random_id()
    
    # Initialize the object with a small payload
    CloudflareDurable.initialize(
      object_id,
      %{initialized_at: DateTime.utc_now(), value: 0},
      worker_url: config.worker_url
    )
  end
  
  @doc false
  defp benchmark_call_method(config, payload_size) do
    # Generate a unique object ID for this benchmark iteration
    object_id = Utils.random_id()
    
    # First, initialize the object
    {:ok, _} = CloudflareDurable.initialize(
      object_id,
      %{initialized_at: DateTime.utc_now(), value: 0},
      worker_url: config.worker_url
    )
    
    # Generate a payload based on the requested size
    payload = case payload_size do
      :small -> %{increment: 1}
      :medium -> %{data: Utils.random_string(1000)}
      :large -> %{data: Utils.random_string(10000)}
    end
    
    # Call a method on the object
    CloudflareDurable.call_method(
      object_id,
      "echo",
      payload,
      worker_url: config.worker_url
    )
  end
  
  @doc false
  defp benchmark_get_state(config) do
    # Generate a unique object ID for this benchmark iteration
    object_id = Utils.random_id()
    
    # First, initialize the object
    {:ok, _} = CloudflareDurable.initialize(
      object_id,
      %{initialized_at: DateTime.utc_now(), value: 0, message: Utils.random_string(100)},
      worker_url: config.worker_url
    )
    
    # Get the object's state
    CloudflareDurable.get_state(object_id, worker_url: config.worker_url)
  end
  
  @doc false
  defp benchmark_update_state(config) do
    # Generate a unique object ID for this benchmark iteration
    object_id = Utils.random_id()
    
    # First, initialize the object
    {:ok, _} = CloudflareDurable.initialize(
      object_id,
      %{initialized_at: DateTime.utc_now(), value: 0},
      worker_url: config.worker_url
    )
    
    # Update a key in the object's state
    CloudflareDurable.update_state(
      object_id,
      "counter",
      :rand.uniform(1000),
      worker_url: config.worker_url
    )
  end
  
  @doc false
  defp benchmark_delete_state(config) do
    # Generate a unique object ID for this benchmark iteration
    object_id = Utils.random_id()
    
    # First, initialize the object
    {:ok, _} = CloudflareDurable.initialize(
      object_id,
      %{initialized_at: DateTime.utc_now(), value: 0, to_delete: "delete me"},
      worker_url: config.worker_url
    )
    
    # Delete a key from the object's state
    CloudflareDurable.delete_state(
      object_id,
      "to_delete",
      worker_url: config.worker_url
    )
  end
end 