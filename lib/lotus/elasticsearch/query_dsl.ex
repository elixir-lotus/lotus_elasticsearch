defmodule Lotus.Elasticsearch.QueryDSL do
  @moduledoc false
  # JSON query manipulation for Elasticsearch/OpenSearch.

  def inject_filters(query_json, []), do: query_json

  def inject_filters(query_json, filters) do
    query_json
    |> Jason.decode!()
    |> do_inject_filters(filters)
    |> Jason.encode!()
  end

  def inject_sorts(query_json, []), do: query_json

  def inject_sorts(query_json, sorts) do
    query_json
    |> Jason.decode!()
    |> Map.put("sort", Enum.map(sorts, &build_sort/1))
    |> Jason.encode!()
  end

  def inject_pagination(query_json, offset, limit) do
    query_json
    |> Jason.decode!()
    |> Map.merge(%{"from" => offset, "size" => limit})
    |> Jason.encode!()
  end

  def extract_indices(_query_json), do: :all

  # --- Private ---

  defp do_inject_filters(query_map, filters) do
    existing_query = Map.get(query_map, "query", %{"match_all" => %{}})
    filter_clauses = Enum.map(filters, &build_filter/1)

    bool_query = wrap_in_bool(existing_query, filter_clauses)
    Map.put(query_map, "query", bool_query)
  end

  defp wrap_in_bool(%{"bool" => bool}, filter_clauses) do
    existing_filter = Map.get(bool, "filter", [])
    %{"bool" => Map.put(bool, "filter", existing_filter ++ filter_clauses)}
  end

  defp wrap_in_bool(existing_query, filter_clauses) do
    %{
      "bool" => %{
        "must" => [existing_query],
        "filter" => filter_clauses
      }
    }
  end

  defp build_filter(%{column: col, op: :eq, value: val}),
    do: %{"term" => %{col => val}}

  defp build_filter(%{column: col, op: :neq, value: val}),
    do: %{"bool" => %{"must_not" => [%{"term" => %{col => val}}]}}

  defp build_filter(%{column: col, op: :gt, value: val}),
    do: %{"range" => %{col => %{"gt" => val}}}

  defp build_filter(%{column: col, op: :gte, value: val}),
    do: %{"range" => %{col => %{"gte" => val}}}

  defp build_filter(%{column: col, op: :lt, value: val}),
    do: %{"range" => %{col => %{"lt" => val}}}

  defp build_filter(%{column: col, op: :lte, value: val}),
    do: %{"range" => %{col => %{"lte" => val}}}

  defp build_filter(%{column: col, op: :like, value: val}),
    do: %{"wildcard" => %{col => %{"value" => "*#{val}*"}}}

  defp build_filter(%{column: col, op: :is_null}),
    do: %{"bool" => %{"must_not" => [%{"exists" => %{"field" => col}}]}}

  defp build_filter(%{column: col, op: :is_not_null}),
    do: %{"exists" => %{"field" => col}}

  defp build_sort(%{column: col, direction: dir}),
    do: %{col => %{"order" => to_string(dir)}}
end
