defmodule Lotus.Source.Adapters.Elasticsearch.EditorConfig do
  @moduledoc false

  def config do
    %{
      language: "json:elasticsearch",
      keywords: query_keywords() ++ aggregation_keywords() ++ meta_keywords(),
      types: field_types(),
      functions: query_functions() ++ aggregation_functions(),
      context_boundaries: []
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
    ~w(aggs aggregations terms date_histogram histogram
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
