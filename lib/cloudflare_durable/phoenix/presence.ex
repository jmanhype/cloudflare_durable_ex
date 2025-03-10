defmodule CloudflareDurable.Phoenix.Presence do
  @moduledoc """
  Tracks presence of clients connected to Durable Object channels.
  
  This module utilizes Phoenix.Presence to track clients that are
  connected to specific Durable Objects, enabling features like
  user lists and real-time presence indicators.
  """
  
  use Phoenix.Presence, 
    otp_app: :cloudflare_durable,
    pubsub_server: CloudflareDurable.Phoenix.PubSub
end 