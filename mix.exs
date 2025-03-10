defmodule CloudflareDurable.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/jmanhype/cloudflare_durable_ex"
  @description """
  An Elixir client for Cloudflare Durable Objects, providing a simple interface for 
  distributed state management, WebSocket connections, and method invocation.
  """

  def project do
    [
      app: :cloudflare_durable,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: @description,
      package: package(),
      docs: docs(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {CloudflareDurable.App, []}
    ]
  end

  defp deps do
    [
      # HTTP client
      {:finch, "~> 0.16"},
      # JSON encoding/decoding
      {:jason, "~> 1.4"},
      # WebSocket client
      {:mint_web_socket, "~> 1.0"},
      # Utilities
      {:telemetry, "~> 1.2"},
      # Testing and documentation
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:excoveralls, "~> 0.16", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.3", only: [:dev, :test], runtime: false},
      {:mock, "~> 0.3.7", only: :test},
      # Benchmarking
      {:benchee, "~> 1.1", only: [:dev, :test]},
      {:benchee_html, "~> 1.0", only: [:dev, :test]}
    ]
  end

  defp package do
    [
      name: "cloudflare_durable",
      maintainers: ["jmanhype"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      files: ~w(lib priv mix.exs README.md CHANGELOG.md LICENSE CONTRIBUTING.md .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md", 
        "CONTRIBUTING.md",
        "LICENSE"
      ],
      groups_for_modules: [
        "Core": [
          CloudflareDurable,
          CloudflareDurable.Client
        ],
        "WebSocket": [
          CloudflareDurable.WebSocket.Connection,
          CloudflareDurable.WebSocket.Supervisor
        ]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end 