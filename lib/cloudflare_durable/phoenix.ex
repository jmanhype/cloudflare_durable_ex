if Code.ensure_loaded?(Phoenix) do
  defmodule CloudflareDurable.Phoenix do
    @moduledoc """
    Phoenix adapter for CloudflareDurable.
    
    This module provides the public API for integrating CloudflareDurable
    with Phoenix applications, including LiveView, Channels, and PubSub.
    It acts as a convenient interface to the adapter's functionality.
    """
    
    alias CloudflareDurable.Phoenix.DurableServer
    
    @doc """
    Starts a GenServer representing a Durable Object.
    
    ## Parameters
    
    * `object_id` - The ID of the Durable Object
    * `opts` - Options to pass to the server
    
    ## Returns
    
    * `{:ok, pid}` - If the server was started
    * `{:error, reason}` - If the server could not be started
    """
    @spec start_durable_server(String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
    def start_durable_server(object_id, opts \\ []) do
      DynamicSupervisor.start_child(
        CloudflareDurable.Phoenix.ServerSupervisor,
        {DurableServer, [object_id, opts]}
      )
    end
    
    @doc """
    Gets state from a Durable Object.
    
    ## Parameters
    
    * `object_id` - The ID of the Durable Object
    * `key` - Optional specific key to retrieve
    
    ## Returns
    
    * `{:ok, value}` - The state value
    * `{:error, reason}` - If there was an error
    """
    @spec get_state(String.t(), String.t() | nil) :: {:ok, any()} | {:error, term()}
    def get_state(object_id, key \\ nil) do
      case get_server(object_id) do
        {:ok, server} -> DurableServer.get_state(server, key)
        error -> error
      end
    end
    
    @doc """
    Updates state in a Durable Object.
    
    ## Parameters
    
    * `object_id` - The ID of the Durable Object
    * `key` - The key to update
    * `value` - The new value
    
    ## Returns
    
    * `:ok` - If the update was successful
    * `{:error, reason}` - If there was an error
    """
    @spec update_state(String.t(), String.t(), any()) :: :ok | {:error, term()}
    def update_state(object_id, key, value) do
      case get_server(object_id) do
        {:ok, server} -> DurableServer.update_state(server, key, value)
        error -> error
      end
    end
    
    @doc """
    Calls a method on a Durable Object.
    
    ## Parameters
    
    * `object_id` - The ID of the Durable Object
    * `method` - The method to call
    * `params` - Parameters to pass to the method
    
    ## Returns
    
    * `{:ok, result}` - The result of the method call
    * `{:error, reason}` - If there was an error
    """
    @spec call_method(String.t(), String.t(), map()) :: {:ok, any()} | {:error, term()}
    def call_method(object_id, method, params \\ %{}) do
      case get_server(object_id) do
        {:ok, server} -> DurableServer.call_method(server, method, params)
        error -> error
      end
    end
    
    @doc """
    Subscribes the current process to updates from a Durable Object.
    
    ## Parameters
    
    * `object_id` - The ID of the Durable Object to subscribe to
    
    ## Returns
    
    * `:ok` - If the subscription was successful
    * `{:error, reason}` - If there was an error
    """
    @spec subscribe(String.t()) :: :ok | {:error, term()}
    def subscribe(object_id) do
      Phoenix.PubSub.subscribe(
        CloudflareDurable.Phoenix.PubSub,
        "durable_object:#{object_id}"
      )
    end
    
    @doc """
    Unsubscribes the current process from updates from a Durable Object.
    
    ## Parameters
    
    * `object_id` - The ID of the Durable Object to unsubscribe from
    
    ## Returns
    
    * `:ok` - If the unsubscription was successful
    * `{:error, reason}` - If there was an error
    """
    @spec unsubscribe(String.t()) :: :ok | {:error, term()}
    def unsubscribe(object_id) do
      Phoenix.PubSub.unsubscribe(
        CloudflareDurable.Phoenix.PubSub,
        "durable_object:#{object_id}"
      )
    end
    
    @doc """
    Lists all active Durable Object servers.
    
    Returns a list of {object_id, pid} tuples for all active servers.
    
    ## Returns
    
    * `[{object_id, pid}]` - List of active Durable Object servers
    """
    @spec list_servers() :: [{String.t(), pid()}]
    def list_servers() do
      Registry.select(CloudflareDurable.Phoenix.Registry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    end
    
    # Private helpers
    
    @spec get_server(String.t()) :: {:ok, pid()} | {:error, term()}
    defp get_server(object_id) do
      case start_durable_server(object_id) do
        {:ok, server} -> {:ok, server}
        {:error, {:already_started, _}} -> 
          {:ok, DurableServer.via_tuple(object_id)}
        error -> error
      end
    end
  end
else
  defmodule CloudflareDurable.Phoenix do
    @moduledoc """
    Phoenix adapter for CloudflareDurable.
    
    This module provides integration with Phoenix applications, including LiveView, Channels, and PubSub.
    
    > **Note**: To use this module, you need to add Phoenix as a dependency:
    >
    > ```elixir
    > {:phoenix, "~> 1.7"},
    > {:phoenix_live_view, "~> 0.20"} # If using LiveView
    > ```
    """
    
    @doc """
    This module requires Phoenix to be installed.
    
    Please add `{:phoenix, \"~> 1.7\"} to your dependencies in mix.exs.
    """
    def missing_dependency, do: raise("Phoenix is required but not installed. Add {:phoenix, \"~> 1.7\"} to your dependencies.")
    
    @doc """
    Starts a GenServer representing a Durable Object.
    
    > **Note**: This function requires Phoenix to be installed.
    """
    def start_durable_server(_, _ \\ []), do: missing_dependency()
    
    @doc """
    Gets state from a Durable Object.
    
    > **Note**: This function requires Phoenix to be installed.
    """
    def get_state(_, _ \\ nil), do: missing_dependency()
    
    @doc """
    Updates state in a Durable Object.
    
    > **Note**: This function requires Phoenix to be installed.
    """
    def update_state(_, _, _), do: missing_dependency()
    
    @doc """
    Calls a method on a Durable Object.
    
    > **Note**: This function requires Phoenix to be installed.
    """
    def call_method(_, _, _ \\ %{}), do: missing_dependency()
    
    @doc """
    Subscribes the current process to updates from a Durable Object.
    
    > **Note**: This function requires Phoenix to be installed.
    """
    def subscribe(_), do: missing_dependency()
    
    @doc """
    Unsubscribes the current process from updates from a Durable Object.
    
    > **Note**: This function requires Phoenix to be installed.
    """
    def unsubscribe(_), do: missing_dependency()
    
    @doc """
    Lists all active Durable Object servers.
    
    > **Note**: This function requires Phoenix to be installed.
    """
    def list_servers(), do: missing_dependency()
  end
end 