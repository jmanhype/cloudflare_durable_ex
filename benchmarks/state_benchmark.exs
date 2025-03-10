defmodule CloudflareDurable.Benchmarks.State do
  @moduledoc """
  Benchmarks for Cloudflare Durable Object state operations.
  
  These benchmarks test the performance of the CloudflareDurable.Application
  module when working with state operations against Durable Objects.
  """
  
  alias CloudflareDurable.Application
  
  @doc """
  Run all state operation benchmarks.
  """
  @spec run(keyword()) :: :ok
  def run(opts \\ []) do
    # Get configuration from environment or defaults
    worker_url = System.get_env("BENCHMARK_WORKER_URL", "http://localhost:8787")
    duration = String.to_integer(System.get_env("BENCHMARK_DURATION", "5"))
    concurrency = String.to_integer(System.get_env("BENCHMARK_CONCURRENCY", "4"))
    
    # Initialize the application
    {:ok, app} = Application.start_link([
      url: worker_url,
      id_type: :name,
      object_name: "benchmark_state",
      retry_options: [
        max_attempts: 3,
        backoff_type: :exponential,
        initial_delay: 100
      ]
    ])
    
    # Initialize the application with initial data
    initialize_app_state(app)
    
    # Prepare the benchmarks
    benchmarks = %{
      "State.get (single key)" => fn -> 
        benchmark_get_single_key(app)
      end,
      "State.get_all (multiple keys)" => fn ->
        benchmark_get_multiple_keys(app)
      end,
      "State.put (single key)" => fn ->
        benchmark_put_single_key(app)
      end,
      "State.put_all (multiple keys)" => fn ->
        benchmark_put_multiple_keys(app, 5)
      end,
      "State.update (increment counter)" => fn ->
        benchmark_update_counter(app)
      end,
      "State.delete (single key)" => fn ->
        benchmark_delete_key(app)
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
    
    # Cleanup
    Application.stop(app)
    
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
        file_path = Path.join(results_dir, "state_results_#{date_time}.benchee")
        [{Benchee.Formatters.Console, extended_statistics: true}, {Benchee.Formatters.TaggedSave, path: file_path} | formatters]
      else
        formatters
      end
    
    List.flatten(formatters)
  end
  
  # Initialize the application state with test data
  defp initialize_app_state(app) do
    initial_data = %{
      "counter" => 0,
      "test_key" => "test_value",
      "number" => 42,
      "list" => [1, 2, 3],
      "map" => %{"key" => "value"}
    }
    
    :ok = Application.put_all(app, initial_data)
  end
  
  # Benchmark getting a single key
  defp benchmark_get_single_key(app) do
    Application.get(app, "test_key")
  end
  
  # Benchmark getting multiple keys
  defp benchmark_get_multiple_keys(app) do
    Application.get_all(app, ["test_key", "counter", "number"])
  end
  
  # Benchmark putting a single key
  defp benchmark_put_single_key(app) do
    random_value = :crypto.strong_rand_bytes(10) |> Base.encode64()
    Application.put(app, "random_key", random_value)
  end
  
  # Benchmark putting multiple keys
  defp benchmark_put_multiple_keys(app, count) do
    random_data = 
      1..count
      |> Enum.map(fn _ -> 
        {"random_#{:crypto.strong_rand_bytes(5) |> Base.encode64()}", 
         :crypto.strong_rand_bytes(10) |> Base.encode64()}
      end)
      |> Map.new()
      
    Application.put_all(app, random_data)
  end
  
  # Benchmark updating a counter
  defp benchmark_update_counter(app) do
    Application.update(app, "counter", fn value ->
      (value || 0) + 1
    end)
  end
  
  # Benchmark deleting a key
  defp benchmark_delete_key(app) do
    # First create a random key
    random_key = "delete_#{:crypto.strong_rand_bytes(5) |> Base.encode64()}"
    :ok = Application.put(app, random_key, "to_be_deleted")
    
    # Then delete it
    Application.delete(app, random_key)
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
    
  CloudflareDurable.Benchmarks.State.run(opts)
end 