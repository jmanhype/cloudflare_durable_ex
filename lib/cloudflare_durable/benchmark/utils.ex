defmodule CloudflareDurable.Benchmark.Utils do
  @moduledoc """
  Utility functions for benchmarks.
  
  This module provides common utility functions used by the benchmark modules.
  """
  
  @doc """
  Generates a random ID for use in benchmarks.
  
  ## Returns
  
    * `String.t()` - A random string ID
  """
  @spec random_id() :: String.t()
  def random_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end
  
  @doc """
  Generates a random string of the specified length.
  
  ## Parameters
  
    * `length` - The length of the random string to generate
  
  ## Returns
  
    * `String.t()` - A random string of the specified length
  """
  @spec random_string(non_neg_integer()) :: String.t()
  def random_string(length) do
    :crypto.strong_rand_bytes(length)
    |> Base.encode64()
    |> binary_part(0, length)
  end
  
  @doc """
  Gets a timestamp for use in filenames.
  
  ## Returns
  
    * `String.t()` - A timestamp string in the format "YYYYMMDD_HHMMSS"
  """
  @spec timestamp() :: String.t()
  def timestamp do
    {{year, month, day}, {hour, minute, second}} = :calendar.local_time()
    
    :io_lib.format(
      "~4..0B~2..0B~2..0B_~2..0B~2..0B~2..0B", 
      [year, month, day, hour, minute, second]
    )
    |> IO.iodata_to_binary()
  end
  
  @doc """
  Creates a directory if it doesn't exist.
  
  ## Parameters
  
    * `path` - The path to create
  
  ## Returns
  
    * `:ok` - The directory was created or already exists
  """
  @spec ensure_dir(String.t()) :: :ok
  def ensure_dir(path) do
    unless File.exists?(path) do
      File.mkdir_p!(path)
    end
    :ok
  end
  
  @doc """
  Summarizes benchmark results for the console.
  
  ## Parameters
  
    * `results` - The benchmark results
  
  ## Returns
  
    * `String.t()` - A string summarizing the results
  """
  @spec summarize_results(map()) :: String.t()
  def summarize_results(results) do
    results
    |> Map.keys()
    |> Enum.map(fn scenario ->
      stats = results[scenario].statistics
      
      avg_time = stats.average
      |> format_time()
      
      p99_time = stats.percentiles["99"]
      |> format_time()
      
      memory = if stats.memory_usage do
        stats.memory_usage.average
        |> format_bytes()
      else
        "N/A"
      end
      
      "#{scenario}: avg=#{avg_time}, p99=#{p99_time}, memory=#{memory}"
    end)
    |> Enum.join("\n")
  end
  
  @doc """
  Formats a time value in the most appropriate unit.
  
  ## Parameters
  
    * `time_ns` - The time in nanoseconds
  
  ## Returns
  
    * `String.t()` - A formatted time string
  """
  @spec format_time(float()) :: String.t()
  def format_time(time_ns) when time_ns < 1_000 do
    "#{Float.round(time_ns, 2)} ns"
  end
  
  def format_time(time_ns) when time_ns < 1_000_000 do
    "#{Float.round(time_ns / 1_000, 2)} μs"
  end
  
  def format_time(time_ns) when time_ns < 1_000_000_000 do
    "#{Float.round(time_ns / 1_000_000, 2)} ms"
  end
  
  def format_time(time_ns) do
    "#{Float.round(time_ns / 1_000_000_000, 2)} s"
  end
  
  @doc """
  Formats a byte size in the most appropriate unit.
  
  ## Parameters
  
    * `bytes` - The size in bytes
  
  ## Returns
  
    * `String.t()` - A formatted size string
  """
  @spec format_bytes(float()) :: String.t()
  def format_bytes(bytes) when bytes < 1_024 do
    "#{Float.round(bytes, 2)} B"
  end
  
  def format_bytes(bytes) when bytes < 1_048_576 do
    "#{Float.round(bytes / 1_024, 2)} KB"
  end
  
  def format_bytes(bytes) when bytes < 1_073_741_824 do
    "#{Float.round(bytes / 1_048_576, 2)} MB"
  end
  
  def format_bytes(bytes) do
    "#{Float.round(bytes / 1_073_741_824, 2)} GB"
  end
end 