# The connection form is Lotus v2's (`Lotus.Source.Connections`); under
# Lotus v1 there is nothing to test.
if Code.ensure_loaded?(Lotus.Source.Adapter.Connection) do
  defmodule Lotus.Elasticsearch.ConnectionTest do
    use ExUnit.Case, async: false

    alias Lotus.Source.Adapters.Elasticsearch
    alias Lotus.Source.Connections

    setup do
      previous = Application.get_env(:lotus, :source_adapters)
      Application.put_env(:lotus, :source_adapters, [Elasticsearch])
      Lotus.Config.reload!()

      on_exit(fn ->
        if previous,
          do: Application.put_env(:lotus, :source_adapters, previous),
          else: Application.delete_env(:lotus, :source_adapters)

        Lotus.Config.reload!()
      end)
    end

    test "offers an Elasticsearch form" do
      assert %{label: "Elasticsearch", module: Elasticsearch, fields: fields} =
               Connections.kind("elasticsearch")

      assert Enum.map(fields, & &1.key) == [:url, :username, :password]
    end

    test "builds the source wrap/2 takes" do
      assert {:ok, adapter} =
               Connections.build("search", "elasticsearch", %{
                 "url" => "https://search.internal:9200",
                 "username" => "lotus",
                 "password" => "secret"
               })

      assert adapter.module == Elasticsearch
      assert adapter.state.url == "https://search.internal:9200"
      assert adapter.state.http_opts[:username] == "lotus"
    end

    test "the URL must be http or https" do
      assert {:error, %{url: "Use an http:// or https:// address."}} =
               Connections.build("search", "elasticsearch", %{"url" => "search.internal"})

      assert {:error, %{url: "Give the url."}} = Connections.build("search", "elasticsearch", %{})
    end

    test "a test says why it could not reach the cluster" do
      assert {:error, message} =
               Connections.test("elasticsearch", %{"url" => "http://127.0.0.1:1"})

      assert message =~ "refused"
    end
  end
end
