defmodule Lotus.Elasticsearch.AdapterTest do
  use ExUnit.Case, async: true

  alias Lotus.Source.Adapters.Elasticsearch, as: Adapter
  alias Lotus.Source.Adapter, as: AdapterStruct

  defmodule TestClient do
    use Lotus.Elasticsearch, otp_app: :lotus_elasticsearch
  end

  describe "can_handle?/1" do
    test "returns true for Elasticsearch client module" do
      assert Adapter.can_handle?(TestClient)
    end

    test "returns true for config map with adapter: :elasticsearch" do
      assert Adapter.can_handle?(%{adapter: :elasticsearch, url: "http://localhost:9200"})
    end

    test "returns false for random module" do
      refute Adapter.can_handle?(String)
    end
  end

  describe "wrap/2" do
    setup do
      Application.put_env(:lotus_elasticsearch, TestClient, url: "http://localhost:9200")
      on_exit(fn -> Application.delete_env(:lotus_elasticsearch, TestClient) end)
    end

    test "wraps client module into adapter struct" do
      adapter = Adapter.wrap("search", TestClient)
      assert %AdapterStruct{name: "search", module: Adapter} = adapter
      assert adapter.state.url == "http://localhost:9200"
    end

    test "wraps config map into adapter struct" do
      config = %{adapter: :elasticsearch, url: "http://localhost:9200"}
      adapter = Adapter.wrap("search", config)
      assert %AdapterStruct{name: "search", module: Adapter} = adapter
      assert adapter.state.url == "http://localhost:9200"
    end
  end

  describe "source identity" do
    setup do
      Application.put_env(:lotus_elasticsearch, TestClient, url: "http://localhost:9200")
      adapter = Adapter.wrap("search", TestClient)
      on_exit(fn -> Application.delete_env(:lotus_elasticsearch, TestClient) end)
      %{adapter: adapter}
    end

    test "source_type", %{adapter: adapter} do
      assert Adapter.source_type(adapter.state) == :elasticsearch
    end

    test "query_language", %{adapter: adapter} do
      assert Adapter.query_language(adapter.state) == "json:elasticsearch"
    end

    test "hierarchy_label", %{adapter: adapter} do
      assert Adapter.hierarchy_label(adapter.state) == "Indices"
    end
  end

  describe "editor_config" do
    test "returns json_dsl language with ES query types" do
      config = Adapter.editor_config(%{})
      assert config.language == "json:elasticsearch"
      assert "match" in config.keywords
      assert "bool" in config.keywords
      assert "aggs" in config.keywords
      assert "text" in config.types
      assert "keyword" in config.types
      assert length(config.functions) > 0
    end
  end

  describe "sanitize_query/3" do
    test "accepts valid JSON" do
      assert :ok = Adapter.sanitize_query(%{}, ~s({"query": {"match_all": {}}}), [])
    end

    test "rejects invalid JSON" do
      assert {:error, "Invalid JSON query"} = Adapter.sanitize_query(%{}, "not json", [])
    end
  end
end
