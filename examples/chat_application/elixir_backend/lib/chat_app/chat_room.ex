defmodule ChatApp.ChatRoom do
  @moduledoc """
  The ChatRoom module handles interaction with a Cloudflare Durable Object
  chat room. It maintains a WebSocket connection to the Durable Object and
  provides functions for sending messages and managing the room.
  """
  use GenServer
  require Logger

  alias Phoenix.PubSub

  @type t :: %__MODULE__{
    room_id: String.t(),
    client: CloudflareDurable.Client.t(),
    durable_object_id: String.t() | nil,
    websocket: pid() | nil,
    state: :connecting | :connected | :disconnected,
    users: map(),
    messages: list()
  }

  defstruct room_id: nil,
            client: nil,
            durable_object_id: nil,
            websocket: nil,
            state: :disconnected,
            users: %{},
            messages: []

  @doc """
  Starts a new ChatRoom process.

  ## Parameters

    * `room_id` - The unique identifier for the chat room
    * `opts` - Additional options for the GenServer

  ## Returns

    * `{:ok, pid}` - The PID of the started process
    * `{:error, reason}` - If the process fails to start
  """
  @spec start_link(String.t(), keyword()) :: GenServer.on_start()
  def start_link(room_id, opts \\ []) do
    GenServer.start_link(__MODULE__, room_id, opts)
  end

  @doc """
  Sends a chat message to the room.

  ## Parameters

    * `room` - The PID of the chat room
    * `username` - The username of the sender
    * `message` - The message text

  ## Returns

    * `:ok` - If the message was sent successfully
    * `{:error, reason}` - If the message could not be sent
  """
  @spec send_message(GenServer.server(), String.t(), String.t()) :: :ok | {:error, any()}
  def send_message(room, username, message) do
    GenServer.call(room, {:send_message, username, message})
  end

  @doc """
  Sets the username for a user in the chat room.

  ## Parameters

    * `room` - The PID of the chat room
    * `user_id` - The unique identifier for the user
    * `username` - The username to set

  ## Returns

    * `:ok` - If the username was set successfully
    * `{:error, reason}` - If the username could not be set
  """
  @spec set_username(GenServer.server(), String.t(), String.t()) :: :ok | {:error, any()}
  def set_username(room, user_id, username) do
    GenServer.call(room, {:set_username, user_id, username})
  end

  @doc """
  Gets the current list of users in the chat room.

  ## Parameters

    * `room` - The PID of the chat room

  ## Returns

    * `list` - A list of user maps with :user_id and :username keys
  """
  @spec get_users(GenServer.server()) :: list(map())
  def get_users(room) do
    GenServer.call(room, :get_users)
  end

  @doc """
  Gets the recent message history for the chat room.

  ## Parameters

    * `room` - The PID of the chat room

  ## Returns

    * `list` - A list of message maps
  """
  @spec get_messages(GenServer.server()) :: list(map())
  def get_messages(room) do
    GenServer.call(room, :get_messages)
  end

  @doc """
  Gets the current connection state of the chat room.

  ## Parameters

    * `room` - The PID of the chat room

  ## Returns

    * `:connecting` - The room is currently connecting to the Durable Object
    * `:connected` - The room is connected to the Durable Object
    * `:disconnected` - The room is disconnected from the Durable Object
  """
  @spec get_state(GenServer.server()) :: :connecting | :connected | :disconnected
  def get_state(room) do
    GenServer.call(room, :get_state)
  end

  # GenServer callbacks

  @impl true
  def init(room_id) do
    # Get the Cloudflare Durable Objects client
    client = ChatApp.DurableClient

    # Create an initial state
    state = %__MODULE__{
      room_id: room_id,
      client: client,
      state: :connecting
    }

    # Start the connection process asynchronously
    Process.send_after(self(), :connect_to_durable_object, 0)

    {:ok, state}
  end

  @impl true
  def handle_call({:send_message, username, message}, _from, state) do
    if state.websocket do
      # Send the message over the WebSocket
      data = Jason.encode!(%{
        type: "message",
        text: message
      })
      
      result = CloudflareDurable.WebSocket.Connection.send_message(state.websocket, data)
      {:reply, result, state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl true
  def handle_call({:set_username, user_id, username}, _from, state) do
    if state.websocket do
      # Send the username over the WebSocket
      data = Jason.encode!(%{
        type: "setUsername",
        username: username
      })
      
      result = CloudflareDurable.WebSocket.Connection.send_message(state.websocket, data)
      {:reply, result, state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl true
  def handle_call(:get_users, _from, state) do
    users = Map.values(state.users)
    {:reply, users, state}
  end

  @impl true
  def handle_call(:get_messages, _from, state) do
    {:reply, state.messages, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.state, state}
  end

  @impl true
  def handle_info(:connect_to_durable_object, state) do
    # Find the Durable Object ID for the chat room
    with {:ok, durable_object_id} <- CloudflareDurable.Client.get_namespace_object(
            state.client,
            "CHATROOM",
            state.room_id
          ),
         # Open a WebSocket connection to the Durable Object
         {:ok, websocket} <- CloudflareDurable.Client.websocket_connect(
            state.client,
            durable_object_id,
            "/",
            subscriber: self()
          ) do
      Logger.info("Connected to chat room Durable Object: #{state.room_id}")
      
      {:noreply, %{state | durable_object_id: durable_object_id, websocket: websocket, state: :connected}}
    else
      error ->
        Logger.error("Failed to connect to chat room Durable Object: #{inspect(error)}")
        # Retry the connection after a delay
        Process.send_after(self(), :connect_to_durable_object, 5000)
        {:noreply, %{state | state: :disconnected}}
    end
  end

  @impl true
  def handle_info({:websocket_message, message}, state) do
    # Parse and handle WebSocket messages from the Durable Object
    case Jason.decode(message) do
      {:ok, data} ->
        handle_websocket_message(data, state)
      {:error, error} ->
        Logger.error("Failed to parse WebSocket message: #{inspect(error)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:websocket_closed, reason}, state) do
    Logger.warn("WebSocket connection closed: #{inspect(reason)}")
    
    # Broadcast the disconnection to subscribers
    PubSub.broadcast(ChatApp.PubSub, "room:#{state.room_id}", {:room_disconnected, state.room_id})
    
    # Try to reconnect after a delay
    Process.send_after(self(), :connect_to_durable_object, 5000)
    
    {:noreply, %{state | websocket: nil, state: :disconnected}}
  end

  # Helper functions

  defp handle_websocket_message(%{"type" => "message", "message" => message}, state) do
    # Add the message to our local state
    updated_messages = [message | state.messages] |> Enum.take(100)
    
    # Broadcast the message to subscribers
    PubSub.broadcast(ChatApp.PubSub, "room:#{state.room_id}", {:new_message, message})
    
    {:noreply, %{state | messages: updated_messages}}
  end

  defp handle_websocket_message(%{"type" => "userList", "users" => users}, state) do
    # Update our local user list
    user_map = users
               |> Enum.map(fn user -> {user["userId"], user} end)
               |> Map.new()
    
    # Broadcast the user list to subscribers
    PubSub.broadcast(ChatApp.PubSub, "room:#{state.room_id}", {:user_list, users})
    
    {:noreply, %{state | users: user_map}}
  end

  defp handle_websocket_message(%{"type" => "history", "messages" => messages}, state) do
    # Update our local message history
    updated_messages = messages |> Enum.take(100)
    
    # Broadcast the history to subscribers
    PubSub.broadcast(ChatApp.PubSub, "room:#{state.room_id}", {:message_history, messages})
    
    {:noreply, %{state | messages: updated_messages}}
  end

  defp handle_websocket_message(%{"type" => "typing", "userId" => user_id, "username" => username, "isTyping" => is_typing}, state) do
    # Broadcast the typing status to subscribers
    PubSub.broadcast(
      ChatApp.PubSub,
      "room:#{state.room_id}",
      {:typing_status, %{user_id: user_id, username: username, is_typing: is_typing}}
    )
    
    {:noreply, state}
  end

  defp handle_websocket_message(message, state) do
    Logger.debug("Unhandled WebSocket message: #{inspect(message)}")
    {:noreply, state}
  end
end 