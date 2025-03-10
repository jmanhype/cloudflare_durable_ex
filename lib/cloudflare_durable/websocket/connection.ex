defmodule CloudflareDurable.WebSocket.Connection do
  @moduledoc """
  WebSocket connection to a Durable Object.
  
  This module manages a WebSocket connection to a Cloudflare Durable Object,
  handling reconnection, message sending, and event handling.
  """
  use GenServer
  require Logger

  @reconnect_msg :reconnect
  @default_backoff_initial 500
  @default_backoff_max 30000

  @type t :: pid()
  @type object_id :: String.t()
  @type websocket_message :: String.t()
  @type connection_status :: :connecting | :connected | :disconnected
  @type connection_state :: %{
    object_id: object_id(),
    url: String.t(),
    conn: map() | nil,
    request: map() | nil,
    status: connection_status(),
    auto_reconnect: boolean(),
    backoff_initial: non_neg_integer(),
    backoff_max: non_neg_integer(),
    current_backoff: non_neg_integer(),
    reconnect_timer: reference() | nil,
    subscribers: [pid()]
  }
  @type connection_opts :: [
    url: String.t(),
    auto_reconnect: boolean(),
    backoff_initial: non_neg_integer(),
    backoff_max: non_neg_integer()
  ]
  @type error_reason :: :not_connected | :network_error | :invalid_message | atom() | String.t()

  # Client API

  @doc """
  Starts a WebSocket connection to a Durable Object.
  
  ## Parameters
    * `object_id` - ID of the Durable Object to connect to
    * `opts` - Connection options:
      * `:url` - WebSocket URL
      * `:auto_reconnect` - Whether to automatically reconnect (default: true)
      * `:backoff_initial` - Initial backoff time in ms (default: 500)
      * `:backoff_max` - Maximum backoff time in ms (default: 30000)
      
  ## Returns
    * `{:ok, pid}` - Successfully started the connection GenServer
    * `{:error, reason}` - Failed to start the connection GenServer
  """
  @spec start_link({object_id(), connection_opts()}) :: GenServer.on_start()
  def start_link({object_id, opts}) do
    GenServer.start_link(__MODULE__, {object_id, opts})
  end
  
  # Also support the format used by the supervisor
  @spec start_link([object_id() | connection_opts()]) :: GenServer.on_start()
  def start_link([object_id, opts]) when is_list(opts) do
    start_link({object_id, opts})
  end

  @doc """
  Sends a message over the WebSocket connection.
  
  ## Parameters
    * `pid` - PID of the connection process
    * `message` - Message to send (will be JSON encoded)
  
  ## Returns
    * `:ok` - Message sent successfully
    * `{:error, reason}` - Failed to send message
  """
  @spec send_message(t(), websocket_message()) :: :ok | {:error, error_reason()}
  def send_message(pid, message) do
    GenServer.call(pid, {:send_message, message})
  end

  @doc """
  Subscribes to messages from the WebSocket connection.
  
  ## Parameters
    * `pid` - PID of the connection process
  
  ## Returns
    * `:ok` - Subscription successful
  """
  @spec subscribe(t()) :: :ok
  def subscribe(pid) do
    GenServer.call(pid, {:subscribe, self()})
  end

  @doc """
  Unsubscribes from messages from the WebSocket connection.
  
  ## Parameters
    * `pid` - PID of the connection process
  
  ## Returns
    * `:ok` - Unsubscription successful
  """
  @spec unsubscribe(t()) :: :ok
  def unsubscribe(pid) do
    GenServer.call(pid, {:unsubscribe, self()})
  end

  @doc """
  Gets the current status of the WebSocket connection.
  
  ## Parameters
    * `pid` - PID of the connection process
    
  ## Returns
    * `:connecting` - Connection is being established
    * `:connected` - Connection is established
    * `:disconnected` - Connection is not established
  """
  @spec status(t()) :: connection_status()
  def status(pid) do
    GenServer.call(pid, :status)
  end

  # Server Callbacks

  @impl true
  @spec init({object_id(), connection_opts()}) :: {:ok, connection_state()}
  def init({object_id, opts}) do
    state = %{
      object_id: object_id,
      url: Keyword.fetch!(opts, :url),
      conn: nil,
      request: nil,
      status: :disconnected,
      auto_reconnect: Keyword.get(opts, :auto_reconnect, true),
      backoff_initial: Keyword.get(opts, :backoff_initial, @default_backoff_initial),
      backoff_max: Keyword.get(opts, :backoff_max, @default_backoff_max),
      current_backoff: 0,
      reconnect_timer: nil,
      subscribers: []
    }

    # Initiate connection
    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case connect(state) do
      {:ok, new_state} ->
        {:noreply, new_state}
      {:error, _reason, new_state} ->
        # Schedule reconnect if enabled
        new_state = maybe_schedule_reconnect(new_state)
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_call({:send_message, message}, _from, %{status: :connected, conn: conn, request: request} = state) do
    case send_websocket_message(conn, request, message) do
      {:ok, conn, request} ->
        {:reply, :ok, %{state | conn: conn, request: request}}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:send_message, _message}, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    # Add the PID to the subscribers list if it's not already there
    if pid in state.subscribers do
      {:reply, :ok, state}
    else
      # Monitor the subscriber to remove it if it dies
      Process.monitor(pid)
      {:reply, :ok, %{state | subscribers: [pid | state.subscribers]}}
    end
  end

  @impl true
  def handle_call({:unsubscribe, pid}, _from, state) do
    # Remove the PID from the subscribers list
    {:reply, :ok, %{state | subscribers: List.delete(state.subscribers, pid)}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  @spec handle_info(term(), connection_state()) :: {:noreply, connection_state()}
  def handle_info({:gun_up, conn_pid, _protocol}, %{conn: %{pid: conn_pid}} = state) do
    Logger.debug("WebSocket connection established")
    
    # Update state to connected
    state = %{state | status: :connected, current_backoff: 0}
    
    {:noreply, state}
  end

  def handle_info({:gun_down, conn_pid, _protocol, reason, _killed_streams}, %{conn: %{pid: conn_pid}} = state) do
    Logger.warning("WebSocket connection down: #{inspect(reason)}")
    
    # Update state to disconnected
    state = %{state |
      status: :disconnected,
      conn: nil,
      request: nil
    }
    
    # Notify subscribers
    broadcast_event({:websocket_closed, reason}, state)
    
    # Schedule reconnect if enabled
    state = maybe_schedule_reconnect(state)
    
    {:noreply, state}
  end

  def handle_info({:gun_ws, conn_pid, _stream_ref, {:text, message}}, %{conn: %{pid: conn_pid}} = state) do
    # Forward the message to all subscribers
    broadcast_event({:websocket_message, message}, state)
    
    {:noreply, state}
  end

  def handle_info({:gun_ws, conn_pid, _stream_ref, {:close, code, reason}}, %{conn: %{pid: conn_pid}} = state) do
    Logger.warning("WebSocket closed with code #{code}: #{reason}")
    
    # Update state to disconnected
    state = %{state |
      status: :disconnected,
      conn: nil,
      request: nil
    }
    
    # Notify subscribers
    broadcast_event({:websocket_closed, "Code #{code}: #{reason}"}, state)
    
    # Schedule reconnect if enabled
    state = maybe_schedule_reconnect(state)
    
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{subscribers: subscribers} = state) do
    # Remove the subscriber if it died
    if pid in subscribers do
      new_subscribers = List.delete(subscribers, pid)
      {:noreply, %{state | subscribers: new_subscribers}}
    else
      # It might be the gun connection that died
      if state.conn && state.conn.pid == pid do
        Logger.warning("WebSocket connection process died: #{inspect(reason)}")
        
        # Update state to disconnected
        state = %{state |
          status: :disconnected,
          conn: nil,
          request: nil
        }
        
        # Notify subscribers
        broadcast_event({:websocket_closed, reason}, state)
        
        # Schedule reconnect if enabled
        state = maybe_schedule_reconnect(state)
      end
      
      {:noreply, state}
    end
  end

  def handle_info(@reconnect_msg, state) do
    # Clear the reconnect timer
    state = %{state | reconnect_timer: nil}
    
    # Attempt to reconnect
    case connect(state) do
      {:ok, new_state} ->
        {:noreply, new_state}
      {:error, _reason, new_state} ->
        # Schedule another reconnect
        new_state = maybe_schedule_reconnect(new_state)
        {:noreply, new_state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  @spec connect(connection_state()) :: {:ok, connection_state()} | {:error, term(), connection_state()}
  defp connect(state) do
    if state.status == :connecting do
      {:error, :already_connecting, state}
    else
      # Update state to connecting
      state = %{state | status: :connecting}
      
      Logger.debug("Connecting to WebSocket: #{state.url}")
      
      # Parse the URL
      uri = URI.parse(state.url)
      
      # Determine the protocol
      protocol = case uri.scheme do
        "ws" -> :http
        "wss" -> :https
        _ -> :http
      end
      
      # Determine the port
      port = uri.port || case protocol do
        :http -> 80
        :https -> 443
      end
      
      # Connect with gun
      gun_opts = %{
        protocols: [:http],
        retry: 0,
        transport: protocol
      }
      
      case :gun.open(to_charlist(uri.host), port, gun_opts) do
        {:ok, conn_pid} ->
          # Wait for the connection to be established
          case :gun.await_up(conn_pid, 5000) do
            {:ok, _protocol} ->
              # Connection established, upgrade to WebSocket
              path = uri.path || "/"
              path = if uri.query, do: "#{path}?#{uri.query}", else: path
              
              # Custom headers
              headers = [
                {"upgrade", "websocket"},
                {"connection", "upgrade"},
                {"sec-websocket-version", "13"},
                {"sec-websocket-key", :base64.encode(crypto_random_bytes(16))}
              ]
              
              # Start the WebSocket handshake
              stream_ref = :gun.ws_upgrade(conn_pid, path, headers)
              
              # Return the updated state
              {:ok, %{state |
                conn: %{pid: conn_pid},
                request: %{stream_ref: stream_ref},
                status: :connecting
              }}
            
            {:error, reason} ->
              # Failed to establish connection
              Logger.error("Failed to establish connection: #{inspect(reason)}")
              
              # Clean up the connection
              :gun.close(conn_pid)
              
              # Return the error
              {:error, reason, %{state | status: :disconnected}}
          end
        
        {:error, reason} ->
          # Failed to open connection
          Logger.error("Failed to open connection: #{inspect(reason)}")
          
          # Return the error
          {:error, reason, %{state | status: :disconnected}}
      end
    end
  end

  @spec send_websocket_message(map(), map(), websocket_message()) :: 
        {:ok, map(), map()} | {:error, error_reason()}
  defp send_websocket_message(conn, request, message) do
    try do
      # Send the message
      :gun.ws_send(conn.pid, request.stream_ref, {:text, message})
      
      # Return the updated connection and request
      {:ok, conn, request}
    rescue
      e ->
        # Log the error
        Logger.error("Failed to send WebSocket message: #{inspect(e)}")
        
        # Return the error
        {:error, :network_error}
    end
  end

  @spec maybe_schedule_reconnect(connection_state()) :: connection_state()
  defp maybe_schedule_reconnect(%{auto_reconnect: false} = state) do
    state
  end
  
  defp maybe_schedule_reconnect(%{reconnect_timer: timer} = state) when not is_nil(timer) do
    state
  end
  
  defp maybe_schedule_reconnect(state) do
    # Calculate the backoff time
    backoff = if state.current_backoff == 0 do
      state.backoff_initial
    else
      min(state.current_backoff * 2, state.backoff_max)
    end
    
    # Schedule the reconnect
    timer = Process.send_after(self(), @reconnect_msg, backoff)
    
    Logger.debug("Scheduling reconnect in #{backoff}ms")
    
    # Update the state
    %{state | current_backoff: backoff, reconnect_timer: timer}
  end

  @spec broadcast_event(term(), connection_state()) :: :ok
  defp broadcast_event(event, state) do
    # Send the event to all subscribers
    Enum.each(state.subscribers, fn pid ->
      send(pid, event)
    end)
    
    :ok
  end

  @spec crypto_random_bytes(non_neg_integer()) :: binary()
  defp crypto_random_bytes(size) do
    :crypto.strong_rand_bytes(size)
  end
end 