defmodule CloudflareDurable.Benchmarks.HTTP do
  @moduledoc """
  Benchmarks for HTTP requests to Cloudflare Workers.
  
  These benchmarks test the performance of various HTTP request patterns
  when interacting with Cloudflare Durable Objects.
  """
  
  @doc """
  Run all HTTP benchmarks.
  """
  @spec run(keyword()) :: :ok
  def run(opts \\ []) do
    # Get configuration from environment or defaults
    worker_url = System.get_env("BENCHMARK_WORKER_URL", "http://localhost:8787")
    duration = String.to_integer(System.get_env("BENCHMARK_DURATION", "5"))
    
    # Prepare HTTP options
    http_opts = [
      pool_timeout: 50_000,
      receive_timeout: 50_000
    ]
    
    # Prepare the benchmarks
    benchmarks = %{
      "HTTP GET (single key)" => fn -> benchmark_get_single_key(worker_url, http_opts) end,
      "HTTP PUT (single key)" => fn -> benchmark_put_single_key(worker_url, http_opts) end,
      "HTTP Method call (echo)" => fn -> benchmark_method_call(worker_url, "echo", http_opts) end,
      "HTTP Method call (increment)" => fn -> benchmark_method_call(worker_url, "increment", http_opts) end,
      "HTTP Method call (set_multiple)" => fn -> benchmark_method_call(worker_url, "set_multiple", http_opts) end
    }
    
    # Initialize the durable object with test data
    initialize_benchmark_object(worker_url, http_opts)
    
    # Run the benchmarks
    Benchee.run(
      benchmarks,
      time: duration,
      memory_time: 2,
      warmup: 2,
      formatters: get_formatters(opts),
      print: [fast_warning: false]
    )
    
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
        file_path = Path.join(results_dir, "http_results_#{date_time}.benchee")
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
    
    {:ok, 200, _headers, _body} = 
      CloudflareDurable.HTTP.request(
        :post,
        url,
        Jason.encode!(initial_data),
        [{"content-type", "application/json"}],
        http_opts
      )
      
    :ok
  end
  
  # Benchmark getting a single key
  defp benchmark_get_single_key(worker_url, http_opts) do
    url = "#{worker_url}/name/benchmark/state/test_key"
    
    {:ok, 200, _headers, body} = 
      CloudflareDurable.HTTP.request(:get, url, "", [], http_opts)
      
    Jason.decode!(body)
  end
  
  # Benchmark putting a single key
  defp benchmark_put_single_key(worker_url, http_opts) do
    url = "#{worker_url}/name/benchmark/state/random_key"
    data = Jason.encode!(%{value: :crypto.strong_rand_bytes(10) |> Base.encode64()})
    
    case CloudflareDurable.HTTP.request(
      :put,
      url,
      data,
      [{"content-type", "application/json"}],
      http_opts
    ) do
      {:ok, status, _headers, body} when status in [200, 201, 404] ->
        Jason.decode!(body)
      other ->
        other
    end
  end
  
  # Benchmark a method call
  defp benchmark_method_call(worker_url, method, http_opts) do
    url = "#{worker_url}/name/benchmark/method/#{method}"
    
    data =
      case method do
        "echo" ->
          Jason.encode!(%{message: "Hello, World!", timestamp: DateTime.utc_now()})
        "increment" ->
          Jason.encode!(%{key: "counter", increment: 1})
        "set_multiple" ->
          random_keys = for _ <- 1..5, into: %{} do
            {random_string(8), random_string(16)}
          end
          Jason.encode!(%{keys: random_keys})
      end
    
    {:ok, 200, _headers, body} = 
      CloudflareDurable.HTTP.request(
        :post,
        url,
        data,
        [{"content-type", "application/json"}],
        http_opts
      )
      
    Jason.decode!(body)
  end
  
  # Generate a random string of specified length
  defp random_string(length) do
    :crypto.strong_rand_bytes(length)
    |> Base.encode64()
    |> binary_part(0, length)
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
    
  CloudflareDurable.Benchmarks.HTTP.run(opts)
end 