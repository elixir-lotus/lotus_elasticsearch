defmodule Lotus.Elasticsearch.QueryDSLTest do
  use ExUnit.Case, async: true

  alias Lotus.Elasticsearch.QueryDSL

  describe "inject_filters/2" do
    test "adds term filter to match_all query" do
      query = ~s({"query": {"match_all": {}}})
      filters = [%{column: "status", op: :eq, value: "active"}]

      result = QueryDSL.inject_filters(query, filters)
      parsed = Jason.decode!(result)

      assert get_in(parsed, ["query", "bool", "must"]) != nil
      assert get_in(parsed, ["query", "bool", "filter"]) != nil
    end

    test "adds range filter for gt operator" do
      query = ~s({"query": {"match_all": {}}})
      filters = [%{column: "age", op: :gt, value: 18}]

      result = QueryDSL.inject_filters(query, filters)
      parsed = Jason.decode!(result)

      filter_clauses = get_in(parsed, ["query", "bool", "filter"])
      assert Enum.any?(filter_clauses, &match?(%{"range" => _}, &1))
    end

    test "preserves existing bool query" do
      query = ~s({"query": {"bool": {"must": [{"match": {"title": "hello"}}]}}})
      filters = [%{column: "status", op: :eq, value: "active"}]

      result = QueryDSL.inject_filters(query, filters)
      parsed = Jason.decode!(result)

      must = get_in(parsed, ["query", "bool", "must"])
      assert length(must) == 1
      assert List.first(must) == %{"match" => %{"title" => "hello"}}
    end

    test "handles empty filters" do
      query = ~s({"query": {"match_all": {}}})
      assert QueryDSL.inject_filters(query, []) == query
    end
  end

  describe "inject_sorts/2" do
    test "adds sort array" do
      query = ~s({"query": {"match_all": {}}})
      sorts = [%{column: "created_at", direction: :desc}]

      result = QueryDSL.inject_sorts(query, sorts)
      parsed = Jason.decode!(result)

      assert parsed["sort"] == [%{"created_at" => %{"order" => "desc"}}]
    end

    test "handles multiple sorts" do
      query = ~s({"query": {"match_all": {}}})

      sorts = [
        %{column: "status", direction: :asc},
        %{column: "created_at", direction: :desc}
      ]

      result = QueryDSL.inject_sorts(query, sorts)
      parsed = Jason.decode!(result)

      assert length(parsed["sort"]) == 2
    end
  end

  describe "inject_pagination/3" do
    test "adds from and size" do
      query = ~s({"query": {"match_all": {}}})

      result = QueryDSL.inject_pagination(query, 20, 10)
      parsed = Jason.decode!(result)

      assert parsed["from"] == 20
      assert parsed["size"] == 10
    end
  end

  describe "extract_indices/1" do
    test "returns :all for a standard query" do
      query = ~s({"query": {"match_all": {}}})
      assert QueryDSL.extract_indices(query) == :all
    end
  end
end
