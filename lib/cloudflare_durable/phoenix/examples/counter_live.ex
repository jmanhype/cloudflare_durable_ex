defmodule CloudflareDurable.Phoenix.Examples.CounterLive do
  @moduledoc """
  Example LiveView for a Durable Object counter.
  
  This module demonstrates how to use the CloudflareDurable.Phoenix adapter
  with a Phoenix LiveView to create a real-time, globally distributed counter.
  """
  
  use Phoenix.LiveView
  alias CloudflareDurable.Phoenix
  
  @doc """
  Mounts the LiveView.
  
  Gets the counter ID from URL parameters or uses a default,
  and subscribes to updates for that counter.
  """
  def mount(params, _session, socket) do
    # Get the counter ID from URL or create a new one
    counter_id = Map.get(params, "id", "default-counter")
    
    if connected?(socket) do
      # Subscribe to counter updates
      Phoenix.subscribe(counter_id)
    end
    
    # Ensure the counter exists with initial value
    {:ok, counter} = Phoenix.get_state(counter_id)
    
    # Initialize with 0 if counter doesn't exist
    if map_size(counter) == 0 do
      Phoenix.update_state(counter_id, "value", 0)
    end
    
    socket = assign(socket, 
      counter_id: counter_id,
      value: counter["value"] || 0
    )
    
    {:ok, socket}
  end
  
  @doc """
  Handles the increment event.
  """
  def handle_event("increment", _params, socket) do
    counter_id = socket.assigns.counter_id
    current = socket.assigns.value
    
    :ok = Phoenix.update_state(counter_id, "value", current + 1)
    
    {:noreply, socket}
  end
  
  @doc """
  Handles the decrement event.
  """
  def handle_event("decrement", _params, socket) do
    counter_id = socket.assigns.counter_id
    current = socket.assigns.value
    
    :ok = Phoenix.update_state(counter_id, "value", current - 1)
    
    {:noreply, socket}
  end
  
  @doc """
  Handles the reset event.
  """
  def handle_event("reset", _params, socket) do
    counter_id = socket.assigns.counter_id
    
    :ok = Phoenix.update_state(counter_id, "value", 0)
    
    {:noreply, socket}
  end
  
  @doc """
  Handles Durable Object state updates.
  """
  def handle_info({:durable_object_update, _id, %{"value" => new_value}}, socket) do
    {:noreply, assign(socket, value: new_value)}
  end
  
  @doc """
  Renders the LiveView.
  """
  def render(assigns) do
    ~H"""
    <div class="counter">
      <h1>Globally Distributed Counter</h1>
      <p>Counter ID: <%= @counter_id %></p>
      
      <div class="value">
        <span class="number"><%= @value %></span>
      </div>
      
      <div class="controls">
        <button phx-click="decrement" class="btn btn-danger">-</button>
        <button phx-click="reset" class="btn btn-secondary">Reset</button>
        <button phx-click="increment" class="btn btn-success">+</button>
      </div>
      
      <div class="admin">
        <h3>Advanced Controls</h3>
        <.live_component
          module={CloudflareDurable.Phoenix.Live.DurableComponent}
          id={"do-admin-#{@counter_id}"}
          object_id={@counter_id}
          title="Counter State"
        />
      </div>
    </div>
    """
  end
end 