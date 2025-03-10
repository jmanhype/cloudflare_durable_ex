#!/usr/bin/env elixir

# Make sure the package is in the code path
Code.prepend_path("_build/dev/lib/cloudflare_durable/ebin")
Code.prepend_path("_build/dev/lib/jason/ebin")
Code.prepend_path("_build/dev/lib/finch/ebin")
Code.prepend_path("_build/dev/lib/mint_web_socket/ebin")
Code.prepend_path("_build/dev/lib/telemetry/ebin")

# Application.ensure_all_started(:cloudflare_durable)

defmodule CounterExample do
  @moduledoc """
  Example showing how to use CloudflareDurable to implement a distributed counter.
  
  This example demonstrates:
  1. Initializing a Durable Object with starting state
  2. Calling methods to modify the Durable Object's state
  3. Retrieving the current state of a Durable Object
  4. Proper error handling and logging

  ## Usage
  
  Set the CLOUDFLARE_WORKER_URL environment variable to your Cloudflare Worker URL
  and run this script:
  
  ```
  CLOUDFLARE_WORKER_URL=https://your-worker.your-account.workers.dev elixir examples/counter.exs
  ```
  
  ## Durable Object Implementation
  
  This example assumes your Durable Object implements:
  - An initialization handler that sets up the counter with a starting value
  - A `method_increment` method that increases the counter by a specified amount
  - Storage of the counter value in the Durable Object's state
  """
  
  @doc """
  Runs the counter example.
  
  This function demonstrates the full lifecycle of a counter Durable Object:
  1. Initialize with a starting value of 0
  2. Increment the counter 5 times
  3. Retrieve the final state
  
  Each step includes proper error handling and logging.
  
  ## Returns
  
  * `:ok` - Example completed successfully (regardless of any errors that occurred)
  """
  @spec run() :: :ok
  def run do
    # Configure the worker URL
    worker_url = get_worker_url()
    Application.put_env(:cloudflare_durable, :worker_url, worker_url)
    
    # Generate a unique counter ID
    counter_id = generate_counter_id()
    IO.puts("Using counter ID: #{counter_id}")
    
    # Run the example
    with {:ok, _} <- initialize_counter(counter_id),
         :ok <- increment_counter(counter_id, 5),
         :ok <- get_final_state(counter_id) do
      IO.puts("\nExample completed successfully.")
    else
      {:error, reason} ->
        IO.puts("\nExample failed: #{inspect(reason)}")
    end
    
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
  Generates a unique counter ID based on the current time.
  
  ## Returns
  
  * `String.t()` - A unique counter ID
  """
  @spec generate_counter_id() :: String.t()
  defp generate_counter_id do
    "counter-#{:os.system_time(:millisecond)}"
  end
  
  @doc """
  Initializes a counter Durable Object with a starting value of 0.
  
  ## Parameters
  
  * `counter_id` - The ID of the counter Durable Object
  
  ## Returns
  
  * `{:ok, map()}` - Successfully initialized counter
  * `{:error, term()}` - Failed to initialize counter
  """
  @spec initialize_counter(String.t()) :: {:ok, map()} | {:error, term()}
  defp initialize_counter(counter_id) do
    case CloudflareDurable.initialize(counter_id, %{value: 0}) do
      {:ok, response} ->
        IO.puts("Initialized counter: #{inspect(response)}")
        {:ok, response}
        
      {:error, reason} = error ->
        IO.puts("Error initializing counter: #{inspect(reason)}")
        error
    end
  end
  
  @doc """
  Increments the counter a specified number of times.
  
  ## Parameters
  
  * `counter_id` - The ID of the counter Durable Object
  * `times` - The number of times to increment the counter
  
  ## Returns
  
  * `:ok` - Successfully incremented counter
  * `{:error, term()}` - Failed to increment counter
  """
  @spec increment_counter(String.t(), non_neg_integer()) :: :ok | {:error, term()}
  defp increment_counter(counter_id, times) do
    increment_counter_recursive(counter_id, 1, times)
  end
  
  @doc """
  Recursive helper function for incrementing the counter.
  
  ## Parameters
  
  * `counter_id` - The ID of the counter Durable Object
  * `current` - The current iteration
  * `total` - The total number of iterations
  
  ## Returns
  
  * `:ok` - Successfully completed all increments
  * `{:error, term()}` - Failed to increment counter
  """
  @spec increment_counter_recursive(String.t(), pos_integer(), non_neg_integer()) :: :ok | {:error, term()}
  defp increment_counter_recursive(_counter_id, current, total) when current > total, do: :ok
  defp increment_counter_recursive(counter_id, current, total) do
    IO.puts("\nIncrementing counter (#{current}/#{total})...")
    
    case CloudflareDurable.call_method(counter_id, "method_increment", %{increment: 1}) do
      {:ok, %{"result" => %{"value" => value}}} ->
        IO.puts("Counter value: #{value}")
        
        # Pause between increments
        Process.sleep(1000)
        
        # Continue with the next increment
        increment_counter_recursive(counter_id, current + 1, total)
        
      {:error, reason} = error ->
        IO.puts("Error incrementing counter: #{inspect(reason)}")
        error
    end
  end
  
  @doc """
  Retrieves the final state of the counter.
  
  ## Parameters
  
  * `counter_id` - The ID of the counter Durable Object
  
  ## Returns
  
  * `:ok` - Successfully retrieved counter state
  * `{:error, term()}` - Failed to retrieve counter state
  """
  @spec get_final_state(String.t()) :: :ok | {:error, term()}
  defp get_final_state(counter_id) do
    case CloudflareDurable.get_state(counter_id) do
      {:ok, state} ->
        IO.puts("\nFinal counter state: #{inspect(state)}")
        :ok
        
      {:error, reason} = error ->
        IO.puts("Error getting counter state: #{inspect(reason)}")
        error
    end
  end
end

CounterExample.run() 