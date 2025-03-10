defmodule CloudflareDurable.Phoenix.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/YourUsername/cloudflare_durable_ex"

  def project do
    [
      app: :cloudflare_durable_phoenix,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  # Run "mix help compile.app" to learn about applications
  def application do
    [
      extra_applications: [:logger],
      mod: {CloudflareDurable.Phoenix.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies
  defp deps do
    [
      {:cloudflare_durable, "~> 0.1"},
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 0.19"},
      {:phoenix_pubsub, "~> 2.1"},
      {:jason, "~> 1.2"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.2", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    Phoenix adapter for CloudflareDurable, providing integration with Phoenix Channels, 
    LiveView, and PubSub for real-time communication with Cloudflare Durable Objects.
    """
  end

  defp package do
    [
      maintainers: ["Your Name"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        "Core": [
          CloudflareDurable.Phoenix,
          CloudflareDurable.Phoenix.Application,
          CloudflareDurable.Phoenix.DurableServer
        ],
        "Phoenix Integration": [
          CloudflareDurable.Phoenix.Channel,
          CloudflareDurable.Phoenix.Presence,
          CloudflareDurable.Phoenix.Live.DurableComponent
        ],
        "Examples": [
          CloudflareDurable.Phoenix.Examples.CounterLive
        ]
      ]
    ]
  end
end 