defmodule CloudflareDurable.Benchmark.State do
  @moduledoc """
  Benchmarks for state operations with Cloudflare Durable Objects.
  
  This module provides benchmarks for measuring the performance of state operations
  with Cloudflare Durable Objects, including bulk operations and persistence scenarios.
  """
  
  require Logger
  alias CloudflareDurable.Benchmark.Utils

  @doc """
  Runs the state operations benchmark suite.
  
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
    IO.puts("\n=== State Operations Benchmarks ===\n")
    IO.puts("Worker URL: #{config.worker_url}")
    IO.puts("Concurrency: #{config.concurrency}")
    IO.puts("Duration: #{config.duration} seconds\n")
    
    # Run the benchmarks
    benchmarks = %{
      "bulk_read_10_keys" => fn -> benchmark_bulk_read(config, 10) end,
      "bulk_read_100_keys" => fn -> benchmark_bulk_read(config, 100) end,
      "bulk_write_10_keys" => fn -> benchmark_bulk_write(config, 10) end,
      "bulk_write_100_keys" => fn -> benchmark_bulk_write(config, 100) end,
      "read_after_write" => fn -> benchmark_read_after_write(config) end,
      "read_write_delete" => fn -> benchmark_read_write_delete(config) end
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
        {Benchee.Formatters.HTML, file: output_path && "#{output_path}/state.html"}
      ],
      print: [fast_warning: false],
      save: save_results && [path: "benchmarks/results/state_#{Utils.timestamp()}.benchee"],
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
  defp benchmark_bulk_read(config, key_count) do
    # Generate a unique object ID for this benchmark iteration
    object_id = Utils.random_id()
    
    # Initialize the object with the specified number of keys
    initial_state = 1..key_count
    |> Enum.map(fn i -> {"key_#{i}", "value_#{i}"} end)
    |> Map.new()
    
    {:ok, _} = CloudflareDurable.initialize(
      object_id,
      initial_state,
      worker_url: config.worker_url
    )
    
    # Get the entire state (which includes all keys)
    CloudflareDurable.get_state(object_id, worker_url: config.worker_url)
  end
  
  @doc false
  defp benchmark_bulk_write(config, key_count) do
    # Generate a unique object ID for this benchmark iteration
    object_id = Utils.random_id()
    
    # Initialize the object with an empty state
    {:ok, _} = CloudflareDurable.initialize(
      object_id,
      %{},
      worker_url: config.worker_url
    )
    
    # Create a method call that will write multiple keys at once
    CloudflareDurable.call_method(
      object_id,
      "set_multiple",
      %{
        keys: 1..key_count
        |> Enum.map(fn i -> {"key_#{i}", "value_#{i}"} end)
        |> Map.new()
      },
      worker_url: config.worker_url
    )
  end
  
  @doc false
  defp benchmark_read_after_write(config) do
    # Generate a unique object ID for this benchmark iteration
    object_id = Utils.random_id()
    
    # Initialize the object with a simple state
    {:ok, _} = CloudflareDurable.initialize(
      object_id,
      %{counter: 0},
      worker_url: config.worker_url
    )
    
    # Update the counter
    {:ok, _} = CloudflareDurable.update_state(
      object_id,
      "counter",
      1,
      worker_url: config.worker_url
    )
    
    # Read the updated counter
    CloudflareDurable.get_state(object_id, "counter", worker_url: config.worker_url)
  end
  
  @doc false
  defp benchmark_read_write_delete(config) do
    # Generate a unique object ID for this benchmark iteration
    object_id = Utils.random_id()
    
    # Initialize the object with a simple state
    {:ok, _} = CloudflareDurable.initialize(
      object_id,
      %{temp: "to be deleted", permanent: "keep me"},
      worker_url: config.worker_url
    )
    
    # Read a key
    {:ok, _} = CloudflareDurable.get_state(
      object_id, 
      "permanent", 
      worker_url: config.worker_url
    )
    
    # Update a key
    {:ok, _} = CloudflareDurable.update_state(
      object_id,
      "permanent",
      "updated value",
      worker_url: config.worker_url
    )
    
    # Delete a key
    CloudflareDurable.delete_state(
      object_id,
      "temp",
      worker_url: config.worker_url
    )
  end
end 