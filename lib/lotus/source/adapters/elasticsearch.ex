defmodule Lotus.Source.Adapters.Elasticsearch do
  @moduledoc false

  @behaviour Lotus.Source.Adapter

  alias Lotus.Elasticsearch.Client
  alias Lotus.Elasticsearch.Introspection
  alias Lotus.Elasticsearch.QueryDSL
  alias Lotus.Elasticsearch.TypeMapper
  alias Lotus.Source.Adapter, as: AdapterStruct

  # --- Resolution ---

  @impl true
  def can_handle?(entry) when is_atom(entry) and not is_nil(entry) do
    function_exported?(entry, :__elasticsearch__, 0)
  end

  def can_handle?(%{adapter: :elasticsearch}), do: true
  def can_handle?(_), do: false

  @impl true
  def wrap(name, entry) when is_atom(entry) do
    config = entry.config()
    build_adapter(name, config)
  end

  def wrap(name, %{} = config) do
    build_adapter(name, Map.to_list(config))
  end

  defp build_adapter(name, config) do
    url = config[:url]
    username = config[:username]
    password = config[:password]

    %AdapterStruct{
      name: name,
      module: __MODULE__,
      state: %{
        url: url,
        username: username,
        password: password,
        http_opts: build_http_opts(username, password)
      },
      source_type: :elasticsearch
    }
  end

  defp build_http_opts(nil, _), do: []
  defp build_http_opts(username, password), do: [username: username, password: password]

  # --- Query Execution ---

  @impl true
  def execute_query(state, query_json, _params, opts) do
    index = Keyword.get(opts, :index, "_all")
    timeout = Keyword.get(opts, :timeout, 15_000)

    query = Jason.decode!(query_json)

    case Client.search(state.url, index, query, state.http_opts ++ [timeout: timeout]) do
      {:ok, response} ->
        {columns, rows} = hits_to_tabular(response)
        {:ok, %{columns: columns, rows: rows, num_rows: length(rows)}}

      {:error, %{status: status, body: body}} ->
        message = extract_error_message(body)
        {:error, "Elasticsearch Error (#{status}): #{message}"}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}
    end
  rescue
    e in [Jason.DecodeError] ->
      {:error, "Invalid JSON query: #{Exception.message(e)}"}

    e ->
      {:error, Exception.message(e)}
  end

  # --- Introspection ---

  @impl true
  def list_schemas(_state), do: {:ok, []}

  @impl true
  def list_tables(state, _schemas, _opts) do
    indices = Introspection.list_indices(state.url, state.http_opts)
    {:ok, Enum.map(indices, &{nil, &1})}
  end

  @impl true
  def get_table_schema(state, _schema, index) do
    columns = Introspection.get_index_mapping(state.url, index, state.http_opts)
    {:ok, columns}
  end

  @impl true
  def resolve_table_schema(_state, _table, _schemas), do: {:ok, nil}

  # --- Identity ---

  @impl true
  def source_type(_state), do: :elasticsearch

  @impl true
  def query_language(_state), do: "json:elasticsearch"

  @impl true
  def supports_feature?(_state, :json), do: true
  @impl true
  def supports_feature?(_state, :arrays), do: true
  @impl true
  def supports_feature?(_state, _), do: false

  @impl true
  def hierarchy_label(_state), do: "Indices"

  @impl true
  def example_query(_state, _index, _schema) do
    ~s|{\n  "query": {\n    "match_all": {}\n  },\n  "size": 100\n}|
  end

  @impl true
  def editor_config(_state) do
    Lotus.Source.Adapters.Elasticsearch.EditorConfig.config()
  end

  # --- SQL Generation (adapted for JSON DSL) ---

  @impl true
  def quote_identifier(_state, identifier), do: identifier

  @impl true
  def param_placeholder(_state, _idx, _var, _type), do: ""

  @impl true
  def limit_offset_placeholders(_state, _limit_idx, _offset_idx), do: {"", ""}

  @impl true
  def apply_filters(_state, query_json, _params, filters) do
    dsl_filters = Enum.map(filters, &to_dsl_filter/1)
    {QueryDSL.inject_filters(query_json, dsl_filters), []}
  end

  @impl true
  def apply_sorts(_state, query_json, sorts) do
    dsl_sorts = Enum.map(sorts, &to_dsl_sort/1)
    QueryDSL.inject_sorts(query_json, dsl_sorts)
  end

  @impl true
  def explain_plan(_state, _query, _params, _opts) do
    {:error, "EXPLAIN is not supported for Elasticsearch"}
  end

  # --- Safety & Visibility ---

  @impl true
  def builtin_denies(_state) do
    # Deny dot-prefixed system indices
    [{nil, ~r/^\./}]
  end

  @impl true
  def builtin_schema_denies(_state), do: []

  @impl true
  def default_schemas(_state), do: []

  # --- Transaction (no-op) ---

  @impl true
  def transaction(state, fun, _opts) do
    {:ok, fun.(state)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  # --- Error Handling ---

  @impl true
  def format_error(_state, %{status: status, body: body}) do
    "Elasticsearch Error (#{status}): #{extract_error_message(body)}"
  end

  def format_error(_state, message) when is_binary(message), do: message
  def format_error(_state, error), do: inspect(error)

  @impl true
  def handled_errors(_state), do: []

  # --- Optional callbacks ---

  @impl true
  def sanitize_query(_state, query, _opts) do
    case Jason.decode(query) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, "Invalid JSON query"}
    end
  end

  @impl true
  def extract_accessed_resources(_state, _query, _params, _opts), do: :skip

  @impl true
  def apply_window(_state, query_json, params, opts) do
    limit = Keyword.fetch!(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    paged = QueryDSL.inject_pagination(query_json, offset, limit)

    window_meta = %{
      window: %{limit: limit, offset: offset},
      total_count: nil,
      total_mode: :none
    }

    {paged, params, window_meta}
  end

  @impl true
  def limit_query(_state, query_json, limit) do
    QueryDSL.inject_pagination(query_json, 0, limit)
  end

  @impl true
  def health_check(state) do
    case Client.request(:get, state.url, "/", state.http_opts) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def disconnect(_state), do: :ok

  @impl true
  def db_type_to_lotus_type(_state, db_type), do: TypeMapper.to_lotus_type(db_type)

  # --- Private helpers ---

  defp hits_to_tabular(%{"hits" => %{"hits" => hits}}) when is_list(hits) and hits != [] do
    sources =
      Enum.map(hits, fn hit ->
        Map.get(hit, "_source", %{})
        |> Map.put("_id", hit["_id"])
        |> Map.put("_index", hit["_index"])
      end)

    all_keys = sources |> Enum.flat_map(&Map.keys/1) |> Enum.uniq() |> Enum.sort()
    columns = all_keys

    rows =
      Enum.map(sources, fn source ->
        Enum.map(all_keys, fn key ->
          case Map.get(source, key) do
            v when is_map(v) or is_list(v) -> Jason.encode!(v)
            v -> v
          end
        end)
      end)

    {columns, rows}
  end

  defp hits_to_tabular(%{"hits" => %{"total" => _}}) do
    {[], []}
  end

  defp hits_to_tabular(%{"aggregations" => aggs}) do
    agg_to_tabular(aggs)
  end

  defp hits_to_tabular(_), do: {[], []}

  defp agg_to_tabular(aggs) do
    case Enum.find(aggs, fn {_k, v} -> is_map(v) and Map.has_key?(v, "buckets") end) do
      {_name, %{"buckets" => buckets}} when is_list(buckets) ->
        columns = buckets |> List.first(%{}) |> Map.keys() |> Enum.sort()

        rows =
          Enum.map(buckets, fn bucket ->
            Enum.map(columns, &Map.get(bucket, &1))
          end)

        {columns, rows}

      _ ->
        columns = Map.keys(aggs) |> Enum.sort()

        values =
          Enum.map(columns, fn key ->
            case aggs[key] do
              %{"value" => v} -> v
              v -> v
            end
          end)

        {columns, [values]}
    end
  end

  defp extract_error_message(%{"error" => %{"type" => type, "reason" => reason}}),
    do: "#{type}: #{reason}"

  defp extract_error_message(%{"error" => %{"reason" => reason}}), do: reason
  defp extract_error_message(%{"error" => error}) when is_binary(error), do: error
  defp extract_error_message(body) when is_binary(body), do: body
  defp extract_error_message(body), do: inspect(body)

  defp to_dsl_filter(%Lotus.Query.Filter{} = f),
    do: %{column: f.column, op: f.op, value: f.value}

  defp to_dsl_sort(%Lotus.Query.Sort{} = s),
    do: %{column: s.column, direction: s.direction}
end
