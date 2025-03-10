defmodule CloudflareDurable.PhoenixCompat do
  @moduledoc false
  # This module handles conditional loading of Phoenix dependencies

  # Check if Phoenix modules are available
  @phoenix_available? Code.ensure_loaded?(Phoenix)
  @phoenix_live_view_available? Code.ensure_loaded?(Phoenix.LiveView)

  def phoenix_available?, do: @phoenix_available?
  def phoenix_live_view_available?, do: @phoenix_live_view_available?

  # Create placeholders for Phoenix modules that will be used in documentation
  if Mix.env() == :dev do
    unless @phoenix_available? do
      defmodule MockPhoenix.PubSub do
        @moduledoc false
        def subscribe(_, _), do: :ok
        def unsubscribe(_, _), do: :ok
        def broadcast(_, _, _), do: :ok
        def broadcast_from(_, _, _, _), do: :ok
      end
    end

    unless @phoenix_live_view_available? do
      defmodule MockPhoenix.LiveView do
        @moduledoc false
        defmacro __using__(_), do: :ok
      end

      defmodule MockPhoenix.LiveComponent do
        @moduledoc false
        defmacro __using__(_), do: :ok
      end

      defmodule MockPhoenix.Channel do
        @moduledoc false
        defmacro __using__(_), do: :ok
      end

      defmodule MockPhoenix.Presence do
        @moduledoc false
        defmacro __using__(_), do: :ok
      end
    end
  end
end 