defmodule ChatApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :chat_app,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ChatApp.Application, []}
    ]
  end

  defp deps do
    [
      # Use local version of cloudflare_durable
      {:cloudflare_durable, path: "../../../"},
      # Phoenix for web framework
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 3.3"},
      {:phoenix_live_view, "~> 0.19"},
      {:phoenix_pubsub, "~> 2.1"},
      # HTTP client
      {:finch, "~> 0.16"},
      # JSON processing
      {:jason, "~> 1.4"},
      # WebSocket client
      {:mint_web_socket, "~> 1.0"}
    ]
  end
end 