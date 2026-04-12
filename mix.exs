defmodule Lotus.Elasticsearch.MixProject do
  use Mix.Project

  def project do
    [
      app: :lotus_elasticsearch,
      version: "0.0.1",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
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
      {:lotus, github: "elixir-lotus/lotus", branch: "refactor/pluggable-adapters"},
      {:req, "~> 0.5"},
      {:ecto_sqlite3, "~> 0.21", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    ["test.setup": ["cmd docker compose up -d"]]
  end
end
