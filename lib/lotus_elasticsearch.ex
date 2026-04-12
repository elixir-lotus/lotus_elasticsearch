defmodule Lotus.Elasticsearch do
  @moduledoc """
  Elasticsearch and OpenSearch adapter for Lotus.

  ## Usage

  Define a client module in your application:

      defmodule MyApp.SearchClient do
        use Lotus.Elasticsearch, otp_app: :my_app
      end

  Then configure it:

      config :my_app, MyApp.SearchClient,
        url: "http://localhost:9200",
        username: "elastic",
        password: "changeme"

  Add it to your Lotus data sources:

      config :lotus,
        source_adapters: [Lotus.Source.Adapters.Elasticsearch],
        data_sources: %{
          "postgres" => MyApp.Repo,
          "search" => MyApp.SearchClient
        }
  """

  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)

    quote do
      @otp_app unquote(otp_app)

      def __elasticsearch__, do: true

      def config do
        Application.get_env(@otp_app, __MODULE__, [])
      end

      def url, do: Keyword.fetch!(config(), :url)
    end
  end
end
