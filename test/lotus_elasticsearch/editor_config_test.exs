defmodule Lotus.Source.Adapters.Elasticsearch.EditorConfigTest do
  use ExUnit.Case, async: true

  alias Lotus.Source.Adapters.Elasticsearch.EditorConfig

  describe "config/0 shape" do
    test "declares the elasticsearch json language" do
      assert EditorConfig.config().language == "json:elasticsearch"
    end

    test "populates keywords, types, functions, and context_boundaries" do
      cfg = EditorConfig.config()
      assert is_list(cfg.keywords) and cfg.keywords != []
      assert is_list(cfg.types) and cfg.types != []
      assert is_list(cfg.functions) and cfg.functions != []
      assert is_list(cfg.context_boundaries)
    end
  end

  describe "context_schema root" do
    setup do
      {:ok, schema: EditorConfig.config().context_schema}
    end

    test "exposes top-level query DSL entry points", %{schema: schema} do
      for key <- ~w(query aggs aggregations sort size from _source
                    highlight track_total_hits timeout collapse search_after) do
        assert key in schema.root, "missing root key: #{key}"
      end
    end
  end

  describe "context_schema children — query layer" do
    setup do
      {:ok, children: EditorConfig.config().context_schema.children}
    end

    test ~s("query" accepts all documented query-type keys), %{children: children} do
      query_children = children["query"]

      for key <- ~w(match match_all match_phrase multi_match term terms range
                    bool exists prefix wildcard regexp fuzzy nested
                    query_string simple_query_string ids) do
        assert key in query_children,
               "expected #{key} under 'query', got: #{inspect(query_children)}"
      end
    end

    test ~s("bool" has exactly the six canonical leaves), %{children: children} do
      assert Enum.sort(children["bool"]) ==
               Enum.sort(~w(must should must_not filter minimum_should_match boost))
    end
  end

  describe "context_schema children — marker rules" do
    setup do
      {:ok, children: EditorConfig.config().context_schema.children}
    end

    test "must/should/must_not/filter all expand as :array_of_query", %{children: children} do
      for key <- ~w(must should must_not filter) do
        assert children[key] == :array_of_query, "expected :array_of_query for #{key}"
      end
    end

    test "leaf-field query keys expand as :fields", %{children: children} do
      for key <- ~w(match match_phrase match_phrase_prefix term terms range
                    prefix wildcard regexp fuzzy) do
        assert children[key] == :fields,
               "expected :fields for #{key}, got #{inspect(children[key])}"
      end
    end

    test ~s("exists" accepts a single "field" key), %{children: children} do
      assert children["exists"] == ["field"]
    end

    test "aggs / aggregations expand as :named_aggregation", %{children: children} do
      assert children["aggs"] == :named_aggregation
      assert children["aggregations"] == :named_aggregation
    end
  end

  describe "context_schema value_literals" do
    setup do
      {:ok, literals: EditorConfig.config().context_schema.value_literals}
    end

    test "sort direction suggests asc/desc", %{literals: literals} do
      assert Enum.sort(literals["order"]) == ["asc", "desc"]
    end

    test "calendar_interval suggests every documented bucket", %{literals: literals} do
      units = literals["calendar_interval"]

      for unit <- ~w(minute hour day week month quarter year) do
        assert unit in units, "missing calendar_interval unit: #{unit}"
      end
    end

    test "fixed_interval is also enumerated", %{literals: literals} do
      units = literals["fixed_interval"]

      for unit <- ~w(ms s m h d) do
        assert unit in units, "missing fixed_interval unit: #{unit}"
      end
    end
  end

  describe "context_schema and flat keywords stay in sync" do
    # `keywords` feeds the ai_context pipeline; every structural entry
    # point (a key that appears in `children`) should also appear in
    # `keywords` so the LLM prompt sees the full vocabulary.
    test "every key in children is in the flat keywords list" do
      cfg = EditorConfig.config()
      flat = MapSet.new(cfg.keywords)

      for {key, _rule} <- cfg.context_schema.children do
        assert MapSet.member?(flat, key),
               "context_schema references #{inspect(key)} but keywords omits it"
      end
    end
  end
end
