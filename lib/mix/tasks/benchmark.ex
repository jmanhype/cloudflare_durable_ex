defmodule Mix.Tasks.Benchmark do
  @moduledoc """
  Mix task to run CloudflareDurable benchmarks.
  
  ## Examples
  
  Run all benchmarks:
  
      mix benchmark
  
  Run specific benchmark categories:
  
      mix benchmark http
      mix benchmark websocket
      mix benchmark state
  
  Run with options:
  
      mix benchmark --output benchmarks/html
      mix benchmark --save
      
  """
  
  use Mix.Task
  
  @shortdoc "Run CloudflareDurable benchmarks"
  
  @impl Mix.Task
  def run(args) do
    # Make sure dependencies are loaded
    Mix.Task.run("app.start")
    
    # Add benchmark files to Code path
    Code.append_path("benchmarks")
    
    # Run the benchmark script with arguments
    Code.require_file("benchmarks/benchmark.exs")
    
    # Run the main benchmark function
    apply(CloudflareDurable.Benchmarks, :main, [args])
  end
end 