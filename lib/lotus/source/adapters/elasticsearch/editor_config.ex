defmodule Lotus.Source.Adapters.Elasticsearch.EditorConfig do
  @moduledoc """
  Editor-side metadata for the Elasticsearch adapter.

  `config/0` returns the payload the adapter hands back from
  `c:Lotus.Source.Adapter.editor_config/1`.
  The map describes the Elasticsearch query DSL the way a code editor
  wants to see it:

    * `:language` — `"json:elasticsearch"`, which selects CodeMirror's
      JSON language and `JsonDslCompletion` on the `lotus_web` side.
    * `:keywords`, `:types`, `:functions` — flat vocabulary lists. Feed
      the "suggest anything" fallback and the AI prompt pipeline.
    * `:context_schema` — the structural schema. `:root` lists valid
      top-level keys; `:children` declares per-parent rules including
      marker atoms (`:fields`, `:array_of_query`, `:named_aggregation`)
      so the editor can propose `must`/`should`/`filter` inside a
      `bool` block, schema field names inside `match`/`term`/`range`,
      etc.; `:value_literals` enumerates fixed value-position
      completions (`"order" → ["asc", "desc"]`, calendar-interval
      units, etc.).

  ## Who consumes this

  `lotus_web` is the primary consumer — its query editor component
  calls `Lotus.Source.editor_config/1`, serializes the payload over
  LiveView, and drives CodeMirror from it. You only need to touch
  this module directly if you're building a custom editor UI on top
  of Lotus (not using `lotus_web`) and want the same structural
  completion data.

  See `Lotus.Source.Adapter` (in `:lotus`) for the authoritative
  typespec of the returned map, and the `:context_schema` /
  `:dialect_spec` documentation there for the full contract.
  """

  def config do
    %{
      language: "json:elasticsearch",
      keywords: query_keywords() ++ aggregation_keywords() ++ meta_keywords(),
      types: field_types(),
      functions: query_functions() ++ aggregation_functions(),
      context_boundaries: [],
      context_schema: context_schema()
    }
  end

  # Structural schema for context-aware editor autocomplete. The web
  # layer walks the cursor's key path and consults this map to decide
  # what's valid at each position. Markers:
  #
  #   :fields             — use schema[index] field names (e.g. inside match/term/range)
  #   :array_of_query     — array of query clauses (inside must/should/…)
  #   :named_aggregation  — user-named bucket (no key suggestions)
  #
  # See Lotus.Source.Adapter.context_schema type in ../lotus.
  defp context_schema do
    %{
      root: root_keys(),
      children: children_rules(),
      value_literals: value_literals()
    }
  end

  defp root_keys do
    ~w(query aggs aggregations sort size from _source highlight
       track_total_hits timeout collapse search_after pit scroll slice
       suggest post_filter rescore script_fields stored_fields
       indices_boost min_score search_type preference routing
       explain version seq_no_primary_term profile)
  end

  defp children_rules do
    Map.merge(
      query_children(),
      Map.merge(aggregation_children(), meta_children())
    )
  end

  defp query_children do
    query_types = ~w(match match_all match_phrase match_phrase_prefix
                     multi_match term terms range bool exists prefix
                     wildcard regexp fuzzy nested query_string
                     simple_query_string ids constant_score dis_max
                     function_score boosting has_child has_parent
                     match_bool_prefix)

    %{
      "query" => query_types,
      "bool" => ~w(must should must_not filter minimum_should_match boost),
      "must" => :array_of_query,
      "should" => :array_of_query,
      "must_not" => :array_of_query,
      "filter" => :array_of_query,
      "match" => :fields,
      "match_phrase" => :fields,
      "match_phrase_prefix" => :fields,
      "term" => :fields,
      "terms" => :fields,
      "range" => :fields,
      "prefix" => :fields,
      "wildcard" => :fields,
      "regexp" => :fields,
      "fuzzy" => :fields,
      "exists" => ["field"],
      "nested" => ~w(path query score_mode ignore_unmapped inner_hits),
      "constant_score" => ~w(filter boost),
      "function_score" => ~w(query functions score_mode boost_mode min_score),
      "dis_max" => ~w(queries tie_breaker boost),
      "boosting" => ~w(positive negative negative_boost)
    }
  end

  defp aggregation_children do
    # Keys that also exist under `query_children/0` (terms, range,
    # filter, filters, nested) intentionally aren't listed here — the
    # single-last-key rule lookup in the web layer can't disambiguate
    # by ancestor, so we keep the query-context meaning as the default
    # and rely on :fields / :named_aggregation for the aggregation-
    # context shapes, which still produce useful suggestions.
    %{
      "aggs" => :named_aggregation,
      "aggregations" => :named_aggregation,
      "date_histogram" => ~w(field calendar_interval fixed_interval
                             time_zone format offset min_doc_count
                             extended_bounds hard_bounds missing order),
      "histogram" => ~w(field interval min_doc_count extended_bounds order),
      "date_range" => ~w(field format ranges time_zone keyed missing)
    }
  end

  defp meta_children do
    %{
      "sort" => :array_of_sort,
      "_source" => ~w(includes excludes),
      "highlight" => ~w(fields pre_tags post_tags type fragment_size
                        number_of_fragments order boundary_scanner
                        boundary_chars fragmenter no_match_size),
      "collapse" => ~w(field inner_hits max_concurrent_group_searches)
    }
  end

  defp value_literals do
    %{
      "order" => ["asc", "desc"],
      "calendar_interval" => ~w(minute hour day week month quarter year 1m 1h 1d 1w 1M 1q 1y),
      "fixed_interval" => ~w(ms s m h d),
      "time_zone" => ~w(UTC +00:00 +01:00 +02:00 -05:00 -08:00),
      "score_mode" => ~w(avg max min sum multiply first),
      "boost_mode" => ~w(multiply replace sum avg max min),
      "type" => ~w(best_fields most_fields cross_fields phrase phrase_prefix bool_prefix),
      "operator" => ~w(and or),
      "zero_terms_query" => ~w(none all),
      "search_type" => ~w(query_then_fetch dfs_query_then_fetch)
    }
  end

  defp query_keywords do
    ~w(query bool must should must_not filter match match_phrase match_all
       term terms range exists prefix wildcard regexp fuzzy
       nested has_child has_parent ids multi_match
       match_phrase_prefix match_bool_prefix
       simple_query_string query_string
       constant_score dis_max function_score boosting)
  end

  defp aggregation_keywords do
    ~w(aggs aggregations terms date_histogram histogram date_range ip_range
       avg sum min max cardinality value_count
       stats extended_stats percentiles percentile_ranks
       top_hits significant_terms rare_terms
       composite auto_date_histogram
       filter filters adjacency_matrix
       nested reverse_nested parent)
  end

  defp meta_keywords do
    ~w(sort size from _source highlight
       track_total_hits timeout search_after
       collapse pit scroll slice
       suggest post_filter rescore
       script_fields stored_fields
       indices_boost min_score
       search_type preference routing)
  end

  defp field_types do
    ~w(text keyword long integer short byte double float half_float scaled_float
       boolean date date_nanos binary ip object nested flattened
       geo_point geo_shape point shape
       completion search_as_you_type
       token_count rank_feature rank_features dense_vector sparse_vector
       alias join)
  end

  defp query_functions do
    [
      %{name: "match", detail: "Full-text search", args: ~s({"field": "value"})},
      %{name: "match_phrase", detail: "Exact phrase match", args: ~s({"field": "phrase"})},
      %{
        name: "multi_match",
        detail: "Multi-field search",
        args: ~s({"query": "text", "fields": []})
      },
      %{name: "term", detail: "Exact value match", args: ~s({"field": "value"})},
      %{name: "terms", detail: "Match any of values", args: ~s({"field": ["v1", "v2"]})},
      %{name: "range", detail: "Range query", args: ~s({"field": {"gte": 0, "lte": 100}})},
      %{name: "exists", detail: "Field exists", args: ~s({"field": "name"})},
      %{name: "prefix", detail: "Prefix match", args: ~s({"field": "prefix"})},
      %{name: "wildcard", detail: "Wildcard match", args: ~s({"field": {"value": "pattern*"}})},
      %{name: "regexp", detail: "Regex match", args: ~s({"field": "pattern"})},
      %{name: "fuzzy", detail: "Fuzzy match", args: ~s({"field": {"value": "text"}})},
      %{
        name: "bool",
        detail: "Boolean combination",
        args: ~s({"must": [], "should": [], "filter": []})
      },
      %{name: "nested", detail: "Query nested objects", args: ~s({"path": "obj", "query": {}})},
      %{name: "query_string", detail: "Lucene query syntax", args: ~s({"query": "field:value"})},
      %{name: "simple_query_string", detail: "Simple query syntax", args: ~s({"query": "text"})}
    ]
  end

  defp aggregation_functions do
    [
      %{name: "terms", detail: "Bucket by field values", args: ~s({"field": "name", "size": 10})},
      %{
        name: "date_histogram",
        detail: "Bucket by date interval",
        args: ~s({"field": "date", "calendar_interval": "day"})
      },
      %{
        name: "histogram",
        detail: "Bucket by numeric range",
        args: ~s({"field": "price", "interval": 10})
      },
      %{name: "avg", detail: "Average metric", args: ~s({"field": "price"})},
      %{name: "sum", detail: "Sum metric", args: ~s({"field": "amount"})},
      %{name: "min", detail: "Minimum metric", args: ~s({"field": "price"})},
      %{name: "max", detail: "Maximum metric", args: ~s({"field": "price"})},
      %{
        name: "cardinality",
        detail: "Approximate distinct count",
        args: ~s({"field": "user_id"})
      },
      %{name: "value_count", detail: "Count of values", args: ~s({"field": "name"})},
      %{name: "stats", detail: "Count, min, max, avg, sum", args: ~s({"field": "price"})},
      %{
        name: "extended_stats",
        detail: "Stats + variance, std dev",
        args: ~s({"field": "price"})
      },
      %{name: "percentiles", detail: "Percentile values", args: ~s({"field": "latency"})},
      %{name: "top_hits", detail: "Top documents per bucket", args: ~s({"size": 3, "sort": []})},
      %{name: "composite", detail: "Paginated multi-bucket", args: ~s({"sources": []})},
      %{
        name: "significant_terms",
        detail: "Statistically unusual terms",
        args: ~s({"field": "text"})
      },
      %{name: "filter", detail: "Single filter bucket", args: ~s({"term": {"status": "active"}})},
      %{name: "filters", detail: "Named filter buckets", args: ~s({"filters": {}})},
      %{
        name: "auto_date_histogram",
        detail: "Auto-interval date buckets",
        args: ~s({"field": "date", "buckets": 10})
      }
    ]
  end
end
