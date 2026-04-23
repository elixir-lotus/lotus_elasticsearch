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
      assert config.functions != []
    end
  end

  describe "sanitize_query/3" do
    alias Lotus.Query.Statement

    test "accepts valid JSON" do
      stmt = %Statement{adapter: Adapter, text: ~s({"query": {"match_all": {}}})}
      assert :ok = Adapter.sanitize_query(%{}, stmt, [])
    end

    test "rejects invalid JSON" do
      stmt = %Statement{adapter: Adapter, text: "not json"}
      assert {:error, reason} = Adapter.sanitize_query(%{}, stmt, [])
      assert reason =~ "Invalid JSON"
    end
  end

  describe "parse_qualified_name/2" do
    test "returns single-component list for any name (ES has a flat namespace)" do
      assert {:ok, ["logs-2025-01"]} = Adapter.parse_qualified_name(%{}, "logs-2025-01")
      assert {:ok, ["app.logs.2025-01"]} = Adapter.parse_qualified_name(%{}, "app.logs.2025-01")
    end
  end

  describe "validate_identifier/3" do
    test ":schema is always ok (ES has no schemas)" do
      assert :ok = Adapter.validate_identifier(%{}, :schema, "anything")
    end

    test ":table enforces ES index naming rules" do
      assert :ok = Adapter.validate_identifier(%{}, :table, "logs-2025-01")
      assert {:error, _} = Adapter.validate_identifier(%{}, :table, "")
      assert {:error, _} = Adapter.validate_identifier(%{}, :table, "-starts-with-dash")
      assert {:error, _} = Adapter.validate_identifier(%{}, :table, "UPPER")
      assert {:error, _} = Adapter.validate_identifier(%{}, :table, "has space")
      assert {:error, _} = Adapter.validate_identifier(%{}, :table, "has|pipe")
    end

    test ":column allows dotted field paths" do
      assert :ok = Adapter.validate_identifier(%{}, :column, "user.email")
      assert {:error, _} = Adapter.validate_identifier(%{}, :column, "")
      assert {:error, _} = Adapter.validate_identifier(%{}, :column, ".leading")
      assert {:error, _} = Adapter.validate_identifier(%{}, :column, "trailing.")
      assert {:error, _} = Adapter.validate_identifier(%{}, :column, " leading_space")
    end
  end

  describe "supported_filter_operators/1" do
    test "returns ES-supported operator atoms" do
      ops = Adapter.supported_filter_operators(%{})
      assert :eq in ops
      assert :like in ops
      assert :is_null in ops
      assert :in in ops
    end
  end

  describe "extract_accessed_resources/2" do
    alias Lotus.Query.Statement

    test "returns {:unrestricted, reason} since ES queries target indices via URL" do
      stmt = %Statement{adapter: Adapter, text: %{"query" => %{"match_all" => %{}}}}
      assert {:unrestricted, reason} = Adapter.extract_accessed_resources(%{}, stmt)
      assert reason =~ "Elasticsearch"
    end
  end

  describe "apply_pagination/3 (Strategy A inline count)" do
    alias Lotus.Query.Statement

    test "count: :exact enables track_total_hits on the body" do
      stmt = %Statement{
        adapter: Adapter,
        text: %{"query" => %{"match_all" => %{}}}
      }

      paged = Adapter.apply_pagination(%{}, stmt, limit: 10, offset: 0, count: :exact)

      assert paged.text["track_total_hits"] == true
      assert paged.text["from"] == 0
      assert paged.text["size"] == 10
      # Strategy A — no count_spec plumbed through meta
      refute Map.has_key?(paged.meta, :count_spec)
    end

    test "count: :none does NOT set track_total_hits (respects ES's default cap)" do
      stmt = %Statement{
        adapter: Adapter,
        text: %{"query" => %{"match_all" => %{}}}
      }

      paged = Adapter.apply_pagination(%{}, stmt, limit: 10, offset: 0, count: :none)

      refute Map.has_key?(paged.text, "track_total_hits")
      refute Map.has_key?(paged.meta, :count_spec)
    end
  end

  describe "ai_context/1" do
    test "declares language, capabilities, and error patterns" do
      assert {:ok, ctx} = Adapter.ai_context(%{})
      assert ctx.language == "json:elasticsearch"
      assert is_binary(ctx.example_query)
      assert is_binary(ctx.syntax_notes)
      assert ctx.capabilities.generation == true
      assert ctx.capabilities.optimization == true
      assert ctx.capabilities.explanation == true
      assert Enum.any?(ctx.error_patterns, &(&1.hint != ""))
    end
  end
end
