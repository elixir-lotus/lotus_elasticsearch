defmodule Lotus.Elasticsearch.QueryDSL do
  @moduledoc false
  # JSON query manipulation for Elasticsearch/OpenSearch.
  #
  # All functions operate on parsed maps. The adapter is responsible for
  # decoding string queries to maps on the way in (via `ensure_map/1`) and
  # encoding to JSON on the way out to the HTTP client.

  @doc "Parse a JSON string into a map, or return the map unchanged."
  def ensure_map(query) when is_map(query), do: {:ok, query}

  def ensure_map(query) when is_binary(query) do
    case Lotus.JSON.decode(query) do
      {:ok, parsed} when is_map(parsed) -> {:ok, parsed}
      {:ok, _} -> {:error, "Query must be a JSON object"}
      {:error, reason} -> {:error, "Invalid JSON: #{inspect(reason)}"}
    end
  end

  def ensure_map(_), do: {:error, "Query must be a JSON object or string"}

  def inject_filters(query_map, []) when is_map(query_map), do: query_map

  def inject_filters(query_map, filters) when is_map(query_map) do
    filter_clauses = Enum.map(filters, &build_filter/1)
    existing_query = Map.get(query_map, "query", %{"match_all" => %{}})
    Map.put(query_map, "query", wrap_in_bool(existing_query, filter_clauses))
  end

  def inject_sorts(query_map, []) when is_map(query_map), do: query_map

  def inject_sorts(query_map, sorts) when is_map(query_map) do
    Map.put(query_map, "sort", Enum.map(sorts, &build_sort/1))
  end

  def inject_pagination(query_map, offset, limit) when is_map(query_map) do
    Map.merge(query_map, %{"from" => offset, "size" => limit})
  end

  @doc "Replace `{{var_name}}` occurrences anywhere in the map with the JSON-encoded value."
  def substitute_variable(query_map, var_name, value) when is_map(query_map) do
    encoded = Lotus.JSON.encode!(value)
    marker = "{{#{var_name}}}"
    # Round-trip through JSON to substitute in string leaves only.
    query_map
    |> Lotus.JSON.encode!()
    |> String.replace("\"#{marker}\"", encoded)
    |> String.replace(marker, encoded)
    |> Lotus.JSON.decode!()
  end

  # --- Private ---

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

  defp build_filter(%{column: col, op: :in, value: vals}) when is_list(vals),
    do: %{"terms" => %{col => vals}}

  defp build_sort(%{column: col, direction: dir}),
    do: %{col => %{"order" => to_string(dir)}}
end
