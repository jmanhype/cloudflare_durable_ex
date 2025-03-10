defmodule CloudflareDurable.Phoenix.Channel do
  @moduledoc """
  Phoenix Channel for real-time communication with Durable Objects.
  
  This module provides the Socket and Channel implementation for
  communicating with Cloudflare Durable Objects in real-time.
  It handles client connections, message routing, and presence tracking.
  """
  
  use Phoenix.Channel
  require Logger
  alias CloudflareDurable.Phoenix.DurableServer
  alias CloudflareDurable.Phoenix.Presence
  
  @doc """
  Handles joining the Durable Object channel.
  
  When a client joins, it will:
  1. Start or get the DurableServer process
  2. Track the client with Presence
  3. Return the current state to the client
  """
  def join("durable_object:" <> object_id, _params, socket) do
    result = DynamicSupervisor.start_child(
      CloudflareDurable.Phoenix.ServerSupervisor,
      {DurableServer, object_id}
    )
    
    case result do
      {:ok, server} ->
        # Set up after join tasks
        send(self(), {:after_join, object_id})
        
        # Get initial state
        {:ok, state} = DurableServer.get_state(server)
        
        {:ok, %{state: state}, assign(socket, :object_id, object_id)}
        
      {:error, {:already_started, _}} ->
        # Server already exists, get its state
        server = DurableServer.via_tuple(object_id)
        {:ok, state} = DurableServer.get_state(server)
        
        send(self(), {:after_join, object_id})
        
        {:ok, %{state: state}, assign(socket, :object_id, object_id)}
        
      {:error, reason} ->
        Logger.error("Failed to start DurableServer: #{inspect(reason)}")
        {:error, %{reason: "Failed to connect to Durable Object"}}
    end
  end
  
  @doc """
  Handles the after_join message.
  
  Sets up Presence tracking and subscribes to Durable Object updates.
  """
  def handle_info({:after_join, object_id}, socket) do
    user_id = socket.assigns[:user_id] || "anonymous-#{inspect(self())}"
    
    {:ok, _} = Presence.track(socket, user_id, %{
      online_at: System.system_time(:second),
      object_id: object_id
    })
    
    # Subscribe to DO updates
    Phoenix.PubSub.subscribe(
      CloudflareDurable.Phoenix.PubSub,
      "durable_object:#{object_id}"
    )
    
    {:noreply, socket}
  end
  
  @doc """
  Handles Durable Object update broadcasts.
  
  When a Durable Object state is updated, this pushes the update
  to the client via the channel.
  """
  def handle_info({:durable_object_update, object_id, update}, socket) 
      when socket.assigns.object_id == object_id do
    push(socket, "state_updated", update)
    {:noreply, socket}
  end
  
  def handle_info({:durable_object_update, _object_id, _update}, socket) do
    # Ignore updates for other objects
    {:noreply, socket}
  end
  
  @doc """
  Handles updating Durable Object state from the client.
  """
  def handle_in("update_state", %{"key" => key, "value" => value}, socket) do
    object_id = socket.assigns.object_id
    server = DurableServer.via_tuple(object_id)
    
    case DurableServer.update_state(server, key, value) do
      :ok ->
        {:reply, :ok, socket}
        
      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end
  
  @doc """
  Handles calling methods on the Durable Object from the client.
  """
  def handle_in("call_method", %{"method" => method} = payload, socket) do
    params = Map.get(payload, "params", %{})
    object_id = socket.assigns.object_id
    server = DurableServer.via_tuple(object_id)
    
    case DurableServer.call_method(server, method, params) do
      {:ok, result} ->
        {:reply, {:ok, %{result: result}}, socket}
        
      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end
  
  @doc """
  Handles explicit refresh requests from the client.
  """
  def handle_in("refresh_state", _params, socket) do
    object_id = socket.assigns.object_id
    server = DurableServer.via_tuple(object_id)
    
    DurableServer.refresh_state(server)
    {:reply, :ok, socket}
  end
end 