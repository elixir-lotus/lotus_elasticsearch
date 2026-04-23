defmodule Lotus.Elasticsearch.QueryDSLTest do
  use ExUnit.Case, async: true

  alias Lotus.Elasticsearch.QueryDSL

  describe "ensure_map/1" do
    test "returns a map unchanged" do
      assert {:ok, %{"query" => %{}}} = QueryDSL.ensure_map(%{"query" => %{}})
    end

    test "decodes a JSON string" do
      assert {:ok, %{"query" => %{"match_all" => %{}}}} =
               QueryDSL.ensure_map(~s({"query": {"match_all": {}}}))
    end

    test "rejects non-object JSON" do
      assert {:error, _} = QueryDSL.ensure_map(~s([1, 2, 3]))
    end

    test "rejects invalid JSON" do
      assert {:error, reason} = QueryDSL.ensure_map("not json")
      assert reason =~ "Invalid JSON"
    end
  end

  describe "inject_filters/2" do
    test "adds term filter to match_all query" do
      query = %{"query" => %{"match_all" => %{}}}
      filters = [%{column: "status", op: :eq, value: "active"}]

      result = QueryDSL.inject_filters(query, filters)

      assert get_in(result, ["query", "bool", "must"]) != nil
      assert get_in(result, ["query", "bool", "filter"]) != nil
    end

    test "adds range filter for gt operator" do
      query = %{"query" => %{"match_all" => %{}}}
      filters = [%{column: "age", op: :gt, value: 18}]

      result = QueryDSL.inject_filters(query, filters)
      filter_clauses = get_in(result, ["query", "bool", "filter"])

      assert Enum.any?(filter_clauses, &match?(%{"range" => _}, &1))
    end

    test "preserves existing bool query" do
      query = %{"query" => %{"bool" => %{"must" => [%{"match" => %{"title" => "hello"}}]}}}
      filters = [%{column: "status", op: :eq, value: "active"}]

      result = QueryDSL.inject_filters(query, filters)
      must = get_in(result, ["query", "bool", "must"])

      assert length(must) == 1
      assert List.first(must) == %{"match" => %{"title" => "hello"}}
    end

    test "handles empty filters" do
      query = %{"query" => %{"match_all" => %{}}}
      assert QueryDSL.inject_filters(query, []) == query
    end

    test "supports :in operator via terms filter" do
      query = %{"query" => %{"match_all" => %{}}}
      filters = [%{column: "status", op: :in, value: ["a", "b"]}]

      result = QueryDSL.inject_filters(query, filters)
      filter_clauses = get_in(result, ["query", "bool", "filter"])

      assert Enum.any?(filter_clauses, &match?(%{"terms" => %{"status" => ["a", "b"]}}, &1))
    end
  end

  describe "inject_sorts/2" do
    test "adds sort array" do
      query = %{"query" => %{"match_all" => %{}}}
      sorts = [%{column: "created_at", direction: :desc}]

      result = QueryDSL.inject_sorts(query, sorts)

      assert result["sort"] == [%{"created_at" => %{"order" => "desc"}}]
    end

    test "handles multiple sorts" do
      query = %{"query" => %{"match_all" => %{}}}

      sorts = [
        %{column: "status", direction: :asc},
        %{column: "created_at", direction: :desc}
      ]

      result = QueryDSL.inject_sorts(query, sorts)
      assert length(result["sort"]) == 2
    end
  end

  describe "inject_pagination/3" do
    test "adds from and size" do
      query = %{"query" => %{"match_all" => %{}}}

      result = QueryDSL.inject_pagination(query, 20, 10)

      assert result["from"] == 20
      assert result["size"] == 10
    end
  end

  describe "substitute_variable/3" do
    test "inlines a JSON-encoded string value at the marker" do
      query = %{"query" => %{"term" => %{"status" => "{{status}}"}}}
      result = QueryDSL.substitute_variable(query, "status", "active")

      assert get_in(result, ["query", "term", "status"]) == "active"
    end

    test "inlines a numeric value without surrounding quotes" do
      query = %{"query" => %{"range" => %{"age" => %{"gte" => "{{min_age}}"}}}}
      result = QueryDSL.substitute_variable(query, "min_age", 18)

      assert get_in(result, ["query", "range", "age", "gte"]) == 18
    end

    test "inlines a list value as a JSON array" do
      query = %{"query" => %{"terms" => %{"tag" => "{{tags}}"}}}
      result = QueryDSL.substitute_variable(query, "tags", ["a", "b"])

      assert get_in(result, ["query", "terms", "tag"]) == ["a", "b"]
    end

    test "leaves unrelated markers in place" do
      query = %{"query" => %{"term" => %{"name" => "{{other}}"}}}
      result = QueryDSL.substitute_variable(query, "status", "active")

      assert get_in(result, ["query", "term", "name"]) == "{{other}}"
    end
  end
end
