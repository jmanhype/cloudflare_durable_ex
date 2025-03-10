defmodule CloudflareDurable.Phoenix.Live.DurableComponent do
  @moduledoc """
  LiveView component for Durable Objects.
  
  This component provides a UI for interacting with Durable Objects,
  including viewing state, updating values, and calling methods.
  It handles real-time updates and provides a consistent user experience.
  """
  
  use Phoenix.LiveComponent
  require Logger
  alias CloudflareDurable.Phoenix.DurableServer
  
  @doc """
  Initializes the component state.
  """
  def mount(socket) do
    {:ok, socket}
  end
  
  @doc """
  Updates the component when new assigns are received.
  
  ## Required Assigns
  
  * `:object_id` - The ID of the Durable Object to display
  
  ## Optional Assigns
  
  * `:title` - Custom title for the component
  * `:allow_updates` - Whether to show update controls (default: true)
  * `:allow_method_calls` - Whether to show method call controls (default: true)
  """
  def update(%{object_id: object_id} = assigns, socket) do
    if connected?(socket) && !Map.get(socket.assigns, :subscribed) do
      Phoenix.PubSub.subscribe(
        CloudflareDurable.Phoenix.PubSub,
        "durable_object:#{object_id}"
      )
    end
    
    # Start or get the server
    result = DynamicSupervisor.start_child(
      CloudflareDurable.Phoenix.ServerSupervisor,
      {DurableServer, object_id}
    )
    
    server = case result do
      {:ok, pid} -> pid
      {:error, {:already_started, _}} -> DurableServer.via_tuple(object_id)
      {:error, reason} -> 
        Logger.error("Failed to start DurableServer: #{inspect(reason)}")
        nil
    end
    
    state = 
      if server do
        {:ok, state} = DurableServer.get_state(server)
        state
      else
        %{}
      end
    
    socket = socket
      |> assign(assigns)
      |> assign(:state, state)
      |> assign(:subscribed, true)
      |> assign(:allow_updates, Map.get(assigns, :allow_updates, true))
      |> assign(:allow_method_calls, Map.get(assigns, :allow_method_calls, true))
      |> assign(:last_error, nil)
    
    {:ok, socket}
  end
  
  @doc """
  Handles client-side events for updating Durable Object state.
  """
  def handle_event("update_state", %{"key" => key, "value" => value}, socket) do
    object_id = socket.assigns.object_id
    server = DurableServer.via_tuple(object_id)
    
    case DurableServer.update_state(server, key, value) do
      :ok ->
        {:noreply, assign(socket, :last_error, nil)}
        
      {:error, reason} ->
        {:noreply, assign(socket, :last_error, "Failed to update: #{inspect(reason)}")}
    end
  end
  
  @doc """
  Handles client-side events for calling methods on the Durable Object.
  """
  def handle_event("call_method", %{"method" => method, "params" => params_json}, socket) do
    object_id = socket.assigns.object_id
    server = DurableServer.via_tuple(object_id)
    
    params = 
      case Jason.decode(params_json) do
        {:ok, decoded} -> decoded
        {:error, _} -> %{}
      end
    
    case DurableServer.call_method(server, method, params) do
      {:ok, result} ->
        {:noreply, socket 
          |> assign(:last_result, result)
          |> assign(:last_error, nil)}
        
      {:error, reason} ->
        {:noreply, socket
          |> assign(:last_error, "Method call failed: #{inspect(reason)}")
          |> assign(:last_result, nil)}
    end
  end
  
  @doc """
  Handles refresh events from the UI.
  """
  def handle_event("refresh", _params, socket) do
    object_id = socket.assigns.object_id
    server = DurableServer.via_tuple(object_id)
    DurableServer.refresh_state(server)
    
    {:noreply, socket}
  end
  
  @doc """
  Handles Durable Object state updates from PubSub.
  """
  def handle_info({:durable_object_update, _object_id, update}, socket) do
    new_state = Map.merge(socket.assigns.state, update)
    {:noreply, assign(socket, :state, new_state)}
  end
  
  @doc """
  Renders the LiveView component.
  """
  def render(assigns) do
    ~H"""
    <div class="durable-object-component" id={@id}>
      <h3><%= @title || "Durable Object: #{@object_id}" %></h3>
      
      <div class="durable-object-state">
        <h4>Current State</h4>
        <pre><%= Jason.encode!(@state, pretty: true) %></pre>
        <button phx-click="refresh" phx-target={@myself} class="btn btn-sm btn-secondary">
          Refresh
        </button>
      </div>
      
      <%= if @allow_updates do %>
        <div class="durable-object-actions">
          <h4>Update State</h4>
          <form phx-submit="update_state" phx-target={@myself}>
            <div class="input-group">
              <input type="text" name="key" placeholder="State key" required class="form-control" />
              <input type="text" name="value" placeholder="State value" required class="form-control" />
              <button type="submit" class="btn btn-primary">Update</button>
            </div>
          </form>
        </div>
      <% end %>
      
      <%= if @allow_method_calls do %>
        <div class="durable-object-method">
          <h4>Call Method</h4>
          <form phx-submit="call_method" phx-target={@myself}>
            <div class="input-group">
              <input type="text" name="method" placeholder="Method name" required class="form-control" />
              <textarea name="params" placeholder='{"key": "value"}' class="form-control">"{}"</textarea>
              <button type="submit" class="btn btn-primary">Call Method</button>
            </div>
          </form>
        </div>
      <% end %>
      
      <%= if Map.has_key?(assigns, :last_result) do %>
        <div class="durable-object-result">
          <h4>Last Result</h4>
          <pre><%= Jason.encode!(@last_result, pretty: true) %></pre>
        </div>
      <% end %>
      
      <%= if @last_error do %>
        <div class="durable-object-error alert alert-danger">
          <p><%= @last_error %></p>
        </div>
      <% end %>
    </div>
    """
  end
end 