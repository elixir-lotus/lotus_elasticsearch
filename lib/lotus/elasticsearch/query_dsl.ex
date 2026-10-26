defmodule Lotus.Elasticsearch.QueryDSL do
  @moduledoc false
  # JSON query manipulation for Elasticsearch/OpenSearch.
  #
  # All functions operate on parsed maps. The adapter is responsible for
  # decoding string queries to maps on the way in (via `ensure_map/1`) and
  # encoding to JSON on the way out to the HTTP client.

  alias Lotus.Query.Tokenizer
  alias Lotus.Query.Tokenizer.Profile

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

  @language "json:elasticsearch"

  @doc "The lexical profile Lotus reads an Elasticsearch statement with."
  def profile, do: Profile.for_language(@language)

  @doc """
  Bind `{{var_name}}` to `value`.

  A text body is read with `Lotus.Query.Tokenizer` and the JSON profile,
  as Lotus core reads it to find the variables, so the template need not
  be valid JSON until every variable is bound:

    * a bare `{{var}}` in code (`"size": {{n}}`) and a string that is only
      the placeholder (`"{{var}}"`) become the value's JSON literal, so a
      number stays a number and a list an array;
    * a placeholder inside a longer string (`"*{{q}}*"`) becomes the
      value's text, escaped for the string.

  A map body (already decoded) can only hold placeholders in strings.
  """
  def substitute_variable(text, var_name, value) when is_binary(text) do
    bind(text, fn
      ^var_name -> {:ok, value}
      _other -> :skip
    end)
  end

  def substitute_variable(query_map, var_name, value) when is_map(query_map) do
    query_map
    |> Lotus.JSON.encode!()
    |> substitute_variable(var_name, value)
    |> Lotus.JSON.decode!()
  end

  @doc """
  Bind every placeholder of `text` to `null`, so the template parses
  without values. A placeholder inside a longer string becomes empty text.
  """
  def neutralize(text) when is_binary(text), do: bind(text, fn _name -> {:ok, nil} end)

  defp bind(text, fun) do
    text
    |> Tokenizer.tokenize(profile())
    |> bind_tokens(fun)
    |> Tokenizer.to_string()
  end

  defp bind_tokens(tokens, fun) do
    Enum.map(tokens, fn
      {:variable, name, _raw} = token ->
        case fun.(name) do
          {:ok, value} -> {:code, Lotus.JSON.encode!(value)}
          :skip -> token
        end

      {:string, raw} ->
        bind_string(raw, fun)

      {:block, inner} ->
        {:block, bind_tokens(inner, fun)}

      token ->
        token
    end)
  end

  defp bind_string(raw, fun) do
    whole =
      case Tokenizer.variables([{:string, raw}]) do
        [name] -> if raw == ~s("{{#{name}}}"), do: name
        _ -> nil
      end

    with name when is_binary(name) <- whole,
         {:ok, value} <- fun.(name) do
      {:code, Lotus.JSON.encode!(value)}
    else
      _ ->
        [{:string, bound}] =
          Tokenizer.replace_variables([{:string, raw}], &string_replacement(&1, fun))

        {:string, bound}
    end
  end

  defp string_replacement(name, fun) do
    case fun.(name) do
      {:ok, value} -> string_text(value)
      :skip -> "{{#{name}}}"
    end
  end

  # The value as the content of a JSON string: its text, escaped, without
  # the quotes.
  defp string_text(nil), do: ""

  defp string_text(value) do
    text = if is_binary(value), do: value, else: Lotus.JSON.encode!(value)
    encoded = Lotus.JSON.encode!(text)
    binary_part(encoded, 1, byte_size(encoded) - 2)
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
