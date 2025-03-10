defmodule ChatApp.RoomManager do
  @moduledoc """
  Manages chat room processes, including starting, finding, and stopping them.
  This module provides functions for working with chat rooms via their IDs.
  """
  require Logger

  @doc """
  Gets a chat room process by ID, starting it if it doesn't exist.

  ## Parameters

    * `room_id` - The unique identifier for the chat room

  ## Returns

    * `{:ok, pid}` - The PID of the chat room process
    * `{:error, reason}` - If the chat room process could not be started
  """
  @spec get_room(String.t()) :: {:ok, pid()} | {:error, any()}
  def get_room(room_id) do
    case find_room(room_id) do
      {:ok, pid} ->
        {:ok, pid}
      {:error, :not_found} ->
        start_room(room_id)
    end
  end

  @doc """
  Finds an existing chat room process by ID.

  ## Parameters

    * `room_id` - The unique identifier for the chat room

  ## Returns

    * `{:ok, pid}` - The PID of the chat room process
    * `{:error, :not_found}` - If the chat room process doesn't exist
  """
  @spec find_room(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def find_room(room_id) do
    case Registry.lookup(ChatApp.RoomRegistry, room_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Starts a new chat room process with the given ID.

  ## Parameters

    * `room_id` - The unique identifier for the chat room

  ## Returns

    * `{:ok, pid}` - The PID of the started chat room process
    * `{:error, reason}` - If the chat room process could not be started
  """
  @spec start_room(String.t()) :: {:ok, pid()} | {:error, any()}
  def start_room(room_id) do
    # Generate a unique name for the room process
    name = {:via, Registry, {ChatApp.RoomRegistry, room_id}}

    # Start the room process under the DynamicSupervisor
    case DynamicSupervisor.start_child(ChatApp.RoomSupervisor, {ChatApp.ChatRoom, room_id, [name: name]}) do
      {:ok, pid} ->
        Logger.info("Started chat room: #{room_id}")
        {:ok, pid}
      {:error, {:already_started, pid}} ->
        Logger.info("Chat room already started: #{room_id}")
        {:ok, pid}
      {:error, reason} ->
        Logger.error("Failed to start chat room: #{room_id}, reason: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Lists all active chat rooms.

  ## Returns

    * `list` - A list of room IDs for all active chat rooms
  """
  @spec list_rooms() :: [String.t()]
  def list_rooms do
    Registry.select(ChatApp.RoomRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @doc """
  Stops a chat room process by ID.

  ## Parameters

    * `room_id` - The unique identifier for the chat room

  ## Returns

    * `:ok` - If the chat room process was stopped
    * `{:error, :not_found}` - If the chat room process doesn't exist
  """
  @spec stop_room(String.t()) :: :ok | {:error, :not_found}
  def stop_room(room_id) do
    case find_room(room_id) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(ChatApp.RoomSupervisor, pid)
        Logger.info("Stopped chat room: #{room_id}")
        :ok
      {:error, :not_found} ->
        {:error, :not_found}
    end
  end
end 