defmodule Lotus.Elasticsearch.MixProject do
  use Mix.Project

  @source_url "https://github.com/elixir-lotus/lotus_elasticsearch"
  @version "1.0.0"

  def project do
    [
      app: :lotus_elasticsearch,
      name: "Lotus Elasticsearch",
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      package: package(),
      description: description(),e
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def cli do
    [preferred_envs: ["test.setup": :test, test: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:lotus, github: "elixir-lotus/lotus", branch: "release/v1.0-prep"},
      {:req, "~> 0.5"},
      {:ecto_sqlite3, "~> 0.21", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    ["test.setup": ["cmd docker compose up -d"]]
  end

  defp package do
    [
      name: "lotus_elasticsearch",
      maintainers: ["Arda Can Tugay", "Rui Freitas"],
      licenses: ["MIT"],
      links: %{GitHub: @source_url},
      files: ~w[lib .formatter.exs mix.exs README* LICENSE*]
    ]
  end

  defp description do
    "Elasticsearch and OpenSearch source adapter for Lotus — run Lotus queries, dashboards, and AI-assisted exploration against Elasticsearch clusters."
  end
end
