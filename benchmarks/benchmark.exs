defmodule CloudflareDurable.Benchmarks do
  @moduledoc """
  Main benchmark runner for CloudflareDurable.
  
  This module coordinates the execution of all benchmark types:
  - HTTP request benchmarks
  - WebSocket benchmarks
  - State operation benchmarks
  
  Run with: `mix run benchmarks/benchmark.exs [options] [category]`
  
  Categories:
  - http: Only run HTTP benchmarks
  - websocket: Only run WebSocket benchmarks
  - state: Only run state operation benchmarks
  
  Options:
  --output, -o: Output HTML report to the specified directory
  --save, -s: Save benchmark results for later comparison
  --compare, -c: Compare with previously saved benchmark results
  """
  
  @doc """
  Run benchmarks based on command line arguments.
  """
  @spec main(list()) :: :ok
  def main(args) do
    # Parse command line arguments
    {opts, categories} = 
      args
      |> OptionParser.parse!(
        aliases: [o: :output, s: :save, c: :compare],
        switches: [output: :string, save: :boolean, compare: :string]
      )
    
    # Determine which benchmarks to run
    run_http = Enum.empty?(categories) or "http" in categories
    run_websocket = Enum.empty?(categories) or "websocket" in categories
    run_state = Enum.empty?(categories) or "state" in categories
    
    # Set the environment variable to execute the benchmarks
    System.put_env("BENCHEE_RUN", "true")
    
    # Run HTTP benchmarks
    if run_http do
      IO.puts("\n===== Running HTTP Benchmarks =====\n")
      Code.require_file("benchmarks/http_benchmark.exs")
      CloudflareDurable.Benchmarks.HTTP.run(opts)
    end
    
    # Run WebSocket benchmarks
    if run_websocket do
      IO.puts("\n===== Running WebSocket Benchmarks =====\n")
      Code.require_file("benchmarks/websocket_benchmark.exs")
      CloudflareDurable.Benchmarks.WebSocket.run(opts)
    end
    
    # Run state operation benchmarks
    if run_state do
      IO.puts("\n===== Running State Operation Benchmarks =====\n")
      Code.require_file("benchmarks/state_benchmark.exs")
      CloudflareDurable.Benchmarks.State.run(opts)
    end
    
    :ok
  end
end

# If this file is executed directly, run the benchmarks
if not Code.ensure_loaded?(Mix) or Mix.Task.recursing?() do
  CloudflareDurable.Benchmarks.main(System.argv())
end 