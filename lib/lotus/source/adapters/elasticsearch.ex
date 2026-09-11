defmodule Lotus.Source.Adapters.Elasticsearch do
  @moduledoc false

  @behaviour Lotus.Source.Adapter

  alias Lotus.Elasticsearch.Client
  alias Lotus.Elasticsearch.Introspection
  alias Lotus.Elasticsearch.QueryDSL
  alias Lotus.Elasticsearch.TypeMapper
  alias Lotus.Query.OptionalClause
  alias Lotus.Query.Statement
  alias Lotus.Source.Adapter, as: AdapterStruct
  alias Lotus.Source.Adapters.Elasticsearch.EditorConfig
  alias Lotus.Variables

  @source_type :elasticsearch
  @language "json:elasticsearch"

  @supported_ops [:eq, :neq, :gt, :gte, :lt, :lte, :like, :is_null, :is_not_null, :in]

  # ---------------------------------------------------------------------------
  # Pluggable registration
  # ---------------------------------------------------------------------------

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
      source_type: @source_type
    }
  end

  defp build_http_opts(nil, _), do: []
  defp build_http_opts(username, password), do: [username: username, password: password]

  # ---------------------------------------------------------------------------
  # Query execution
  # ---------------------------------------------------------------------------

  @impl true
  def execute_query(state, text, _params, opts) do
    index = Keyword.get(opts, :index, "_all")
    timeout = Keyword.get(opts, :timeout, 15_000)

    with {:ok, query_map} <- QueryDSL.ensure_map(text),
         {:ok, response} <-
           Client.search(state.url, index, query_map, state.http_opts ++ [timeout: timeout]) do
      {columns, rows} = hits_to_tabular(response)
      result = %{columns: columns, rows: rows, num_rows: length(rows)}

      # Strategy A (inline count): when apply_pagination/3 set
      # track_total_hits, ES returns an exact `hits.total.value` alongside
      # the page. Surface it so core skips Strategy B.
      case extract_total_hits(response, query_map) do
        nil -> {:ok, result}
        total -> {:ok, Map.put(result, :total_count, total)}
      end
    else
      {:error, %{status: status, body: body}} ->
        {:error, "Elasticsearch Error (#{status}): #{extract_error_message(body)}"}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def transaction(state, fun, _opts) when is_function(fun, 1) do
    {:ok, fun.(state)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  # ---------------------------------------------------------------------------
  # Introspection
  # ---------------------------------------------------------------------------

  @impl true
  def list_schemas(_state), do: {:ok, []}

  @impl true
  def list_tables(state, _schemas, _opts) do
    indices = Introspection.list_indices(state.url, state.http_opts)
    {:ok, Enum.map(indices, &{nil, &1})}
  end

  @impl true
  def describe_table(state, _schema, index) do
    columns = Introspection.get_index_mapping(state.url, index, state.http_opts)
    {:ok, columns}
  end

  @impl true
  def resolve_table_namespace(_state, _table, _schemas), do: {:ok, nil}

  # ---------------------------------------------------------------------------
  # Pipeline
  # ---------------------------------------------------------------------------

  @impl true
  def quote_identifier(_state, identifier), do: identifier

  @impl true
  def apply_filters(_state, %Statement{} = statement, []), do: statement

  def apply_filters(_state, %Statement{} = statement, filters) do
    {:ok, query_map} = QueryDSL.ensure_map(statement.body)
    dsl_filters = Enum.map(filters, &filter_to_dsl/1)
    %{statement | body: QueryDSL.inject_filters(query_map, dsl_filters)}
  end

  @impl true
  def apply_sorts(_state, %Statement{} = statement, []), do: statement

  def apply_sorts(_state, %Statement{} = statement, sorts) do
    {:ok, query_map} = QueryDSL.ensure_map(statement.body)
    dsl_sorts = Enum.map(sorts, &sort_to_dsl/1)
    %{statement | body: QueryDSL.inject_sorts(query_map, dsl_sorts)}
  end

  @impl true
  def apply_pagination(_state, %Statement{} = statement, opts) do
    limit = Keyword.fetch!(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)
    count = Keyword.get(opts, :count, :none)
    {:ok, query_map} = QueryDSL.ensure_map(statement.body)

    paged = QueryDSL.inject_pagination(query_map, offset, limit)

    # Strategy A (inline count): when :exact is requested, enable ES's
    # exact-total tracking on the main query and let execute_query/4 pull
    # the number out of `hits.total.value`. No :count_spec; no second
    # round-trip. See the Lotus source-adapters guide for the precedence
    # rule (inline count wins over count_spec).
    final_text =
      case count do
        :exact -> Map.put(paged, "track_total_hits", true)
        _ -> paged
      end

    %{statement | body: final_text}
  end

  @impl true
  def needs_preflight?(_state, _statement), do: true

  @impl true
  def query_plan(_state, _statement, _opts) do
    # ES has no plan source that's cheap AND useful AND production-safe:
    # the Profile API carries real runtime overhead, `_search?explain` is
    # scoring-only, and `_validate?explain=true`'s rewritten Lucene query
    # tells the LLM nothing the statement + mapping don't already reveal.
    # Returning `{:ok, nil}` tells the optimizer pipeline to review the
    # statement and `describe_table/3` output directly.
    {:ok, nil}
  end

  @impl true
  def substitute_variable(_state, %Statement{} = statement, var_name, value, _type) do
    with {:ok, query_map} <- QueryDSL.ensure_map(statement.body) do
      {:ok, %{statement | body: QueryDSL.substitute_variable(query_map, var_name, value)}}
    end
  end

  @impl true
  def substitute_list_variable(state, %Statement{} = statement, var_name, values, type)
      when is_list(values) do
    substitute_variable(state, statement, var_name, values, type)
  end

  @impl true
  def sanitize_query(_state, %Statement{} = statement, _opts) do
    case QueryDSL.ensure_map(statement.body) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def transform_bound_query(_state, %Statement{} = statement, _opts), do: statement

  @impl true
  def transform_statement(_state, %Statement{} = statement), do: statement

  # ---------------------------------------------------------------------------
  # Visibility
  # ---------------------------------------------------------------------------

  @impl true
  def extract_accessed_resources(_state, _statement) do
    # Elasticsearch queries target indices via the HTTP URL, not the JSON body.
    # Lotus cannot statically determine which indices a body will touch; the
    # host app must opt in via `allow_unrestricted_resources: true` per-source
    # or globally. Index-level security is enforced by ES itself.
    {:unrestricted,
     "Elasticsearch queries target indices via the HTTP URL; visibility " <>
       "must be enforced at the index level (ES security / cluster permissions). " <>
       "Set `allow_unrestricted_resources: true` in the source config to opt in."}
  end

  @impl true
  def builtin_denies(_state) do
    # Dot-prefixed indices are ES system indices (.kibana, .security, …).
    [{nil, ~r/^\./}]
  end

  @impl true
  def builtin_schema_denies(_state), do: []

  @impl true
  def default_schemas(_state), do: []

  # ---------------------------------------------------------------------------
  # Validation & identifier rules
  # ---------------------------------------------------------------------------

  @impl true
  def validate_statement(state, %Statement{} = statement, _opts) do
    with {:ok, query_map} <- QueryDSL.ensure_map(prepare_template(statement.body)) do
      validate_via_es(state, query_map)
    end
  end

  @impl true
  def parse_qualified_name(_state, name) when is_binary(name) do
    # ES has a flat namespace — an index name is a single component. Dots are
    # valid characters inside index names (e.g. "app.logs.2025-01"), so we do
    # NOT split on ".".
    {:ok, [name]}
  end

  @impl true
  def validate_identifier(_state, :schema, _value), do: :ok

  def validate_identifier(_state, :table, value) when is_binary(value) do
    # Elasticsearch index name rules: lowercase, ≤ 255 bytes, cannot start with
    # -, _, +, cannot contain \ / * ? " < > | space , # or :.
    cond do
      byte_size(value) == 0 ->
        {:error, "index name cannot be empty"}

      byte_size(value) > 255 ->
        {:error, "index name exceeds 255 bytes"}

      String.starts_with?(value, ["-", "_", "+"]) ->
        {:error, "index name cannot start with -, _, or +"}

      value != String.downcase(value) ->
        {:error, "index name must be lowercase"}

      Regex.match?(~r{[\\/*?"<>|\s,#:]}, value) ->
        {:error, ~s(index name contains invalid character: \\ / * ? " < > | space , # :)}

      true ->
        :ok
    end
  end

  def validate_identifier(_state, :column, value) when is_binary(value) do
    # Field names: no control chars, no leading/trailing whitespace, no dots
    # at path boundaries (dots inside are legal — nested field paths).
    cond do
      byte_size(value) == 0 -> {:error, "field name cannot be empty"}
      value =~ ~r/\A\s|\s\z/ -> {:error, "field name cannot start or end with whitespace"}
      value =~ ~r/[\x00-\x1f\x7f]/ -> {:error, "field name contains control characters"}
      String.starts_with?(value, ".") -> {:error, "field name cannot start with ."}
      String.ends_with?(value, ".") -> {:error, "field name cannot end with ."}
      true -> :ok
    end
  end

  @impl true
  def supported_filter_operators(_state), do: @supported_ops

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  @impl true
  def health_check(state) do
    case Client.request(:get, state.url, "/", state.http_opts) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def disconnect(_state), do: :ok

  # ---------------------------------------------------------------------------
  # Errors
  # ---------------------------------------------------------------------------

  @impl true
  def format_error(_state, %{status: status, body: body}) do
    "Elasticsearch Error (#{status}): #{extract_error_message(body)}"
  end

  def format_error(_state, message) when is_binary(message), do: message
  def format_error(_state, error), do: inspect(error)

  # ---------------------------------------------------------------------------
  # Identity & presentation
  # ---------------------------------------------------------------------------

  @impl true
  def source_type(_state), do: @source_type

  @impl true
  def supports_feature?(_state, :json), do: true
  def supports_feature?(_state, :arrays), do: true
  # A search returns shaped documents, not a flat column of values, so the
  # UI asks the user to type dropdown options by hand.
  def supports_feature?(_state, :dynamic_options), do: false
  def supports_feature?(_state, _), do: false

  @impl true
  def query_language(_state), do: @language

  @impl true
  def limit_query(_state, statement, limit) when is_binary(statement) do
    # Used for dropdown-option fetching. Caller passes a stringified JSON body.
    case QueryDSL.ensure_map(statement) do
      {:ok, map} -> map |> QueryDSL.inject_pagination(0, limit) |> Lotus.JSON.encode!()
      {:error, _} -> statement
    end
  end

  def limit_query(_state, statement, _limit), do: statement

  @impl true
  def hierarchy_label(_state), do: "Indices"

  @impl true
  def example_query(_state, _index, _schema) do
    ~s|{\n  "query": {\n    "match_all": {}\n  },\n  "size": 100\n}|
  end

  @impl true
  def editor_config(_state) do
    EditorConfig.config()
  end

  @impl true
  def db_type_to_lotus_type(_state, db_type), do: TypeMapper.to_lotus_type(db_type)

  # ---------------------------------------------------------------------------
  # AI context
  # ---------------------------------------------------------------------------

  @impl true
  def ai_context(_state) do
    {:ok,
     %{
       language: @language,
       example_query: ~s|{"query": {"bool": {"filter": [{"term": {"status": "{{status}}"}}]}}}|,
       syntax_notes:
         ~s|Queries are Elasticsearch Query DSL JSON objects. | <>
           ~s|Use `term` for exact match, `match` for analyzed text, `range` for numeric/date ranges, | <>
           ~s|`wildcard` for glob patterns. Wrap multiple clauses in `bool` with `must`/`filter`/`must_not`/`should`. | <>
           ~s|For variables: always wrap `{{var_name}}` in surrounding quotes so the template is valid JSON — | <>
           ~s|the adapter strips the quotes when inlining the JSON-encoded value, so | <>
           ~s|`{"term": {"status": "{{status}}"}}` becomes `{"term": {"status": "active"}}` at runtime | <>
           ~s|(integer/boolean values shed the surrounding quotes automatically). | <>
           ~s|Pagination uses `from`/`size`, not `LIMIT`/`OFFSET`. Aggregations go under `aggs`. | <>
           ~s|Optimization: prefer `bool.filter` over `bool.must` when scoring isn't needed | <>
           ~s|(filter context is cacheable and skips scoring). For exact-match string comparisons use | <>
           ~s|`term` on `.keyword` subfields, not `match` on analyzed `text` fields. Avoid deep `from:` | <>
           ~s|offsets past ~10k — switch to `search_after` with a consistent sort. Leading `*` in | <>
           ~s|`wildcard`/`regexp` queries is slow; an ngram analyzer at index time is the proper fix. | <>
           ~s|Watch aggregation cardinality — use `composite` aggs for high-cardinality `terms`. | <>
           ~s|Sorting and aggregating on a field requires `doc_values: true` in the mapping.|,
       error_patterns: [
         %{
           pattern: ~r/index_not_found_exception/,
           hint: "The index does not exist. List available indices via list_tables."
         },
         %{
           pattern: ~r/mapper_parsing_exception|illegal_argument_exception/,
           hint:
             "Field type mismatch or malformed query. Check the field mapping via describe_table."
         },
         %{
           pattern: ~r/parsing_exception/,
           hint:
             "Query DSL is syntactically invalid. Ensure the JSON object matches ES Query DSL shape."
         }
       ],
       capabilities: %{
         generation: true,
         optimization: true,
         explanation: true
       }
     }}
  end

  @impl true
  def prepare_for_analysis(_state, %Statement{body: text} = statement) when is_binary(text) do
    {:ok, %{statement | body: prepare_template(text), params: []}}
  end

  def prepare_for_analysis(_state, %Statement{} = statement) do
    # Map-typed text — already structurally "prepared"; just clear params.
    {:ok, %{statement | params: []}}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Neutralize Lotus template syntax so the result is valid JSON without any
  # values bound. Used by `validate_statement/3` and `prepare_for_analysis/2` —
  # both inspect the statement without executing, so unresolved `{{var}}`
  # placeholders and `[[...]]` optional blocks must be stripped before
  # JSON-parsing. `null` is the JSON-native analogue of SQL's `NULL`.
  defp prepare_template(text) when is_binary(text) do
    text
    |> OptionalClause.strip_brackets()
    |> Variables.neutralize("null")
  end

  defp prepare_template(text), do: text

  defp validate_via_es(state, query_map) do
    path = "/_validate/query?explain=false"

    case Client.request(:post, state.url, path, state.http_opts ++ [json: query_map]) do
      {:ok, %{body: %{"valid" => true}}} ->
        :ok

      {:ok, %{body: %{"valid" => false} = body}} ->
        reason =
          body
          |> Map.get("explanations", [])
          |> Enum.map_join("; ", fn e -> e["error"] || "invalid query" end)

        {:error, if(reason == "", do: "Query is not valid", else: reason)}

      {:error, %{status: status, body: body}} ->
        {:error, "Elasticsearch Error (#{status}): #{extract_error_message(body)}"}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}
    end
  end

  # Extract the total-hit count from a search response ONLY when the caller's
  # query asked for it via `track_total_hits: true`. Without that flag, ES
  # caps the reported total at 10 000 and may return a `gte` relation — not a
  # trustworthy exact count.
  defp extract_total_hits(%{"hits" => %{"total" => %{"value" => v, "relation" => "eq"}}}, %{
         "track_total_hits" => true
       })
       when is_integer(v),
       do: v

  defp extract_total_hits(_response, _query), do: nil

  defp hits_to_tabular(%{"hits" => %{"hits" => hits}}) when is_list(hits) and hits != [] do
    sources = Enum.map(hits, &normalize_hit/1)
    columns = sources |> Enum.flat_map(&Map.keys/1) |> Enum.uniq() |> Enum.sort()
    rows = Enum.map(sources, &extract_row(&1, columns))
    {columns, rows}
  end

  defp hits_to_tabular(%{"hits" => %{"total" => _}}), do: {[], []}
  defp hits_to_tabular(%{"aggregations" => aggs}), do: agg_to_tabular(aggs)
  defp hits_to_tabular(_), do: {[], []}

  defp normalize_hit(hit) do
    hit
    |> Map.get("_source", %{})
    |> Map.put("_id", hit["_id"])
    |> Map.put("_index", hit["_index"])
  end

  defp extract_row(source, columns) do
    Enum.map(columns, fn key -> encode_cell(Map.get(source, key)) end)
  end

  defp encode_cell(v) when is_map(v) or is_list(v), do: Lotus.JSON.encode!(v)
  defp encode_cell(v), do: v

  defp agg_to_tabular(aggs) do
    case Enum.find(aggs, fn {_k, v} -> is_map(v) and Map.has_key?(v, "buckets") end) do
      {_name, %{"buckets" => buckets}} when is_list(buckets) -> buckets_to_tabular(buckets)
      _ -> metrics_to_tabular(aggs)
    end
  end

  defp buckets_to_tabular(buckets) do
    columns = buckets |> List.first(%{}) |> Map.keys() |> Enum.sort()
    rows = Enum.map(buckets, fn bucket -> Enum.map(columns, &Map.get(bucket, &1)) end)
    {columns, rows}
  end

  defp metrics_to_tabular(aggs) do
    columns = aggs |> Map.keys() |> Enum.sort()
    values = Enum.map(columns, &extract_metric_value(aggs, &1))
    {columns, [values]}
  end

  defp extract_metric_value(aggs, key) do
    case aggs[key] do
      %{"value" => v} -> v
      v -> v
    end
  end

  defp extract_error_message(%{"error" => %{"type" => type, "reason" => reason}}),
    do: "#{type}: #{reason}"

  defp extract_error_message(%{"error" => %{"reason" => reason}}), do: reason
  defp extract_error_message(%{"error" => error}) when is_binary(error), do: error
  defp extract_error_message(body) when is_binary(body), do: body
  defp extract_error_message(body), do: inspect(body)

  defp filter_to_dsl(%Lotus.Query.Filter{} = f),
    do: %{column: f.column, op: f.op, value: f.value}

  defp sort_to_dsl(%Lotus.Query.Sort{} = s),
    do: %{column: s.column, direction: s.direction}
end
