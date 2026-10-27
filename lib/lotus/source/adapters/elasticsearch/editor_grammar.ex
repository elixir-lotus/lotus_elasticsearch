defmodule Lotus.Source.Adapters.Elasticsearch.EditorGrammar do
  @moduledoc """
  The shape of an Elasticsearch search request, for the query editor.

  `grammar/0` is the `:grammar` of the editor config's `:context_schema`.
  Lotus Web walks it along the key path at the cursor, so it knows what each
  position of the request takes: the keys of a `bool`, a field name inside a
  `term`, an aggregation's name and then its type, `"asc"` or `"desc"` for an
  `order`, a date field for a `date_histogram`, an index name for `_index`.
  The flat `:root`, `:children` and `:value_literals` stay for editors that
  do not read it.

  ## Shape

  `%{start: type, types: %{name => type}}`. A type is the name of one of
  `types`, a primitive, or a map:

    * primitives: `"string"`, `"number"`, `"integer"`, `"boolean"`,
      `"any"`, `"field"` (a field of the indices), `"index"` (an index
      name);
    * `%{object: %{key => member}}`: an object with these keys. A member is
      a type, or `%{type: type, doc: text, snippet: text}`, where `snippet`
      is what the editor inserts after `"key": ` (CodeMirror snippet syntax,
      `${}` for the cursor). With `fields: type`, any field of the indices
      is a key too, taking `type`; with `names: type`, any name is (an
      aggregation's); with `indices: type`, any index name is. `one_key:
      true` says the object holds one of its keys (a query clause), and
      `open: true` that other keys are fine; an object without either, and
      without `fields`, `names` or `indices`, takes only its keys;
    * `%{array: type}`: an array of `type`;
    * `%{one_of: [type]}`: any of these, told apart by the JSON value
      (object, array, string…);
    * `%{enum: [value]}`: one of these values;
    * `%{field: [mapping_type]}`: a field name, its mapping types first.
  """

  @numeric ~w(long integer short byte double float half_float scaled_float unsigned_long)
  @dates ~w(date date_nanos)
  @keywords ~w(keyword constant_keyword wildcard ip boolean) ++ @numeric ++ @dates

  @doc "The grammar of a search request body."
  def grammar do
    %{start: "search", types: types()}
  end

  defp types do
    %{}
    |> Map.merge(search_types())
    |> Map.merge(query_types())
    |> Map.merge(aggregation_types())
  end

  # ---------------------------------------------------------------------------
  # The request
  # ---------------------------------------------------------------------------

  defp search_types do
    %{
      "search" => %{
        object: %{
          "query" => m("query", "The query that matches documents", "{ ${} }"),
          "aggs" => m("aggs", "Aggregations over the matching documents", "{ ${} }"),
          "aggregations" => m("aggs", "Aggregations over the matching documents", "{ ${} }"),
          "size" => m("integer", "How many hits to return (10 by default)"),
          "from" => m("integer", "How many hits to skip"),
          "sort" => m("sort", "How to sort the hits", "[ ${} ]"),
          "_source" => m("source_filter", "Which fields of _source to return"),
          "fields" => m(%{array: "field_format"}, "Fields to return, from the mapping"),
          "docvalue_fields" => m(%{array: "field_format"}, "Fields to return from doc values"),
          "stored_fields" =>
            m(%{one_of: ["field", %{array: "field"}]}, "Stored fields to return"),
          "highlight" => m("highlight", "Highlight matches in these fields"),
          "track_total_hits" =>
            m(%{one_of: ["boolean", "integer"]}, "Count every hit (true) or up to a number"),
          "track_scores" => m("boolean", "Compute scores when sorting by a field"),
          "timeout" => m("string", ~s(How long to search, as "2s")),
          "terminate_after" => m("integer", "The most documents to collect per shard"),
          "min_score" => m("number", "Leave out hits that score lower"),
          "post_filter" => m("query", "A filter applied after aggregations", "{ ${} }"),
          "collapse" => m("collapse", "One hit per value of a field"),
          "search_after" => m(%{array: "any"}, "Page after these sort values"),
          "explain" => m("boolean", "Explain how each hit's score was computed"),
          "version" => m("boolean", "Return each hit's version"),
          "seq_no_primary_term" => m("boolean", "Return each hit's sequence number"),
          "indices_boost" => m(%{array: %{object: %{}, indices: "number"}}, "Boost by index"),
          "runtime_mappings" =>
            m(%{object: %{}, names: "runtime_field"}, "Fields computed at search time"),
          "script_fields" =>
            m(%{object: %{}, names: "script_field"}, "Fields computed by a script"),
          "rescore" => m(%{one_of: ["rescore", %{array: "rescore"}]}, "Rescore the top hits"),
          "suggest" => m(%{object: %{}, names: "any", open: true}, "Suggest similar terms"),
          "profile" => m("boolean", "Profile the search"),
          "pit" => m("pit", "Search a point in time"),
          "stats" => m(%{array: "string"}, "Stats groups"),
          "knn" => m(%{one_of: ["knn", %{array: "knn"}]}, "Nearest neighbours of a vector")
        }
      },
      "source_filter" => %{
        one_of: [
          "boolean",
          %{field: []},
          %{array: "field"},
          %{object: %{"includes" => %{array: "field"}, "excludes" => %{array: "field"}}}
        ]
      },
      "field_format" => %{
        one_of: [
          %{field: []},
          %{object: %{"field" => "field", "format" => "string", "include_unmapped" => "boolean"}}
        ]
      },
      "sort" => %{one_of: ["sort_item", %{array: "sort_item"}]},
      "sort_item" => %{
        one_of: [
          %{field: @keywords},
          %{
            object: %{
              "_score" => m(%{one_of: ["sort_order", "sort_options"]}, "Sort by score"),
              "_doc" => m(%{one_of: ["sort_order", "sort_options"]}, "Sort by index order"),
              "_geo_distance" => m(%{object: %{}, open: true}, "Sort by distance"),
              "_script" => m("script_sort", "Sort by a script")
            },
            fields: %{one_of: ["sort_order", "sort_options"]}
          }
        ]
      },
      "sort_order" => %{enum: ["asc", "desc"]},
      "sort_options" => %{
        object: %{
          "order" => "sort_order",
          "mode" => %{enum: ~w(min max sum avg median)},
          "missing" => %{one_of: [%{enum: ["_last", "_first"]}, "any"]},
          "unmapped_type" => %{enum: ~w(long double keyword date boolean)},
          "numeric_type" => %{enum: ~w(double long date date_nanos)},
          "format" => "string",
          "nested" => %{object: %{"path" => %{field: ["nested"]}, "filter" => "query"}}
        }
      },
      "script_sort" => %{
        object: %{
          "type" => %{enum: ["number", "string"]},
          "script" => "script",
          "order" => "sort_order"
        }
      },
      "highlight" => %{
        object: %{
          "fields" =>
            m(
              %{one_of: [%{object: %{}, fields: "highlight_options"}, %{array: "any"}]},
              "Fields to highlight"
            ),
          "pre_tags" => %{array: "string"},
          "post_tags" => %{array: "string"},
          "type" => %{enum: ~w(unified plain fvh)},
          "fragment_size" => "integer",
          "number_of_fragments" => "integer",
          "order" => %{enum: ["score", "none"]},
          "require_field_match" => "boolean",
          "encoder" => %{enum: ["default", "html"]},
          "no_match_size" => "integer",
          "boundary_scanner" => %{enum: ~w(chars sentence word)},
          "highlight_query" => "query"
        }
      },
      "highlight_options" => %{
        object: %{
          "type" => %{enum: ~w(unified plain fvh)},
          "fragment_size" => "integer",
          "number_of_fragments" => "integer",
          "pre_tags" => %{array: "string"},
          "post_tags" => %{array: "string"},
          "no_match_size" => "integer",
          "matched_fields" => %{array: "field"}
        }
      },
      "collapse" => %{
        object: %{
          "field" => %{field: @keywords},
          "inner_hits" => %{one_of: ["inner_hits", %{array: "inner_hits"}]},
          "max_concurrent_group_searches" => "integer"
        }
      },
      "inner_hits" => %{
        object: %{
          "name" => "string",
          "size" => "integer",
          "from" => "integer",
          "sort" => "sort",
          "_source" => "source_filter",
          "collapse" => "collapse",
          "highlight" => "highlight"
        }
      },
      "runtime_field" => %{
        object: %{
          "type" => %{enum: ~w(keyword long double date boolean ip geo_point composite lookup)},
          "script" => "script",
          "format" => "string"
        }
      },
      "script_field" => %{object: %{"script" => "script", "ignore_failure" => "boolean"}},
      "script" => %{
        one_of: [
          "string",
          %{
            object: %{
              "source" => m("string", "The script, in Painless"),
              "id" => "string",
              "lang" => %{enum: ["painless", "expression", "mustache"]},
              "params" => %{object: %{}, open: true}
            }
          }
        ]
      },
      "rescore" => %{
        object: %{
          "window_size" => "integer",
          "query" => %{
            object: %{
              "rescore_query" => "query",
              "query_weight" => "number",
              "rescore_query_weight" => "number",
              "score_mode" => %{enum: ~w(total multiply avg max min)}
            }
          }
        }
      },
      "pit" => %{object: %{"id" => "string", "keep_alive" => "string"}},
      "knn" => %{
        object: %{
          "field" => %{field: ["dense_vector", "knn_vector"]},
          "query_vector" => %{array: "number"},
          "k" => "integer",
          "num_candidates" => "integer",
          "filter" => %{one_of: ["query", %{array: "query"}]},
          "similarity" => "number",
          "boost" => "number"
        }
      }
    }
  end

  # ---------------------------------------------------------------------------
  # Queries
  # ---------------------------------------------------------------------------

  defp query_types do
    %{
      "query" => %{object: query_clauses(), one_key: true},
      "queries" => %{one_of: ["query", %{array: "query"}]},
      "bool" => %{
        object: %{
          "must" => m("queries", "Clauses that must match, and score", "[ ${} ]"),
          "filter" => m("queries", "Clauses that must match, without scoring", "[ ${} ]"),
          "should" => m("queries", "Clauses that should match", "[ ${} ]"),
          "must_not" => m("queries", "Clauses that must not match", "[ ${} ]"),
          "minimum_should_match" =>
            m(%{one_of: ["integer", "string"]}, "How many should clauses must match"),
          "boost" => "number",
          "_name" => "string"
        }
      },
      "match_value" => %{
        one_of: [
          "scalar",
          %{
            object: %{
              "query" => m("scalar", "The text to search for"),
              "operator" => %{enum: ["or", "and"]},
              "minimum_should_match" => %{one_of: ["integer", "string"]},
              "fuzziness" => %{one_of: [%{enum: ["AUTO", "0", "1", "2"]}, "integer"]},
              "analyzer" => "string",
              "zero_terms_query" => %{enum: ["none", "all"]},
              "lenient" => "boolean",
              "prefix_length" => "integer",
              "max_expansions" => "integer",
              "fuzzy_transpositions" => "boolean",
              "auto_generate_synonyms_phrase_query" => "boolean",
              "boost" => "number",
              "_name" => "string"
            }
          }
        ]
      },
      "match_phrase_value" => %{
        one_of: [
          "scalar",
          %{
            object: %{
              "query" => "scalar",
              "slop" => "integer",
              "analyzer" => "string",
              "max_expansions" => "integer",
              "zero_terms_query" => %{enum: ["none", "all"]},
              "boost" => "number",
              "_name" => "string"
            }
          }
        ]
      },
      "multi_match" => %{
        object: %{
          "query" => m("scalar", "The text to search for"),
          "fields" =>
            m(%{array: %{field: ["text", "keyword"]}}, "The fields to search", "[ \"${}\" ]"),
          "type" => %{
            enum: ~w(best_fields most_fields cross_fields phrase phrase_prefix bool_prefix)
          },
          "operator" => %{enum: ["or", "and"]},
          "minimum_should_match" => %{one_of: ["integer", "string"]},
          "tie_breaker" => "number",
          "fuzziness" => %{one_of: [%{enum: ["AUTO", "0", "1", "2"]}, "integer"]},
          "analyzer" => "string",
          "slop" => "integer",
          "lenient" => "boolean",
          "zero_terms_query" => %{enum: ["none", "all"]},
          "boost" => "number",
          "_name" => "string"
        }
      },
      "query_string" => %{
        object: %{
          "query" => m("string", "Lucene query syntax, as status:paid AND total:>10"),
          "default_field" => "field",
          "fields" => %{array: "field"},
          "default_operator" => %{enum: ["OR", "AND"]},
          "analyzer" => "string",
          "allow_leading_wildcard" => "boolean",
          "analyze_wildcard" => "boolean",
          "fuzziness" => %{one_of: [%{enum: ["AUTO"]}, "integer"]},
          "lenient" => "boolean",
          "minimum_should_match" => %{one_of: ["integer", "string"]},
          "time_zone" => "time_zone",
          "boost" => "number",
          "_name" => "string"
        }
      },
      "simple_query_string" => %{
        object: %{
          "query" => "string",
          "fields" => %{array: "field"},
          "default_operator" => %{enum: ["OR", "AND"]},
          "analyzer" => "string",
          "flags" => "string",
          "lenient" => "boolean",
          "minimum_should_match" => %{one_of: ["integer", "string"]},
          "boost" => "number",
          "_name" => "string"
        }
      },
      "combined_fields" => %{
        object: %{
          "query" => "string",
          "fields" => %{array: %{field: ["text"]}},
          "operator" => %{enum: ["or", "and"]},
          "minimum_should_match" => %{one_of: ["integer", "string"]},
          "zero_terms_query" => %{enum: ["none", "all"]},
          "boost" => "number"
        }
      },
      "term_value" => %{
        one_of: [
          "scalar",
          %{
            object: %{
              "value" => "scalar",
              "boost" => "number",
              "case_insensitive" => "boolean",
              "_name" => "string"
            }
          }
        ]
      },
      "range_value" => %{
        object: %{
          "gte" => m("scalar", "Greater than or equal to"),
          "gt" => m("scalar", "Greater than"),
          "lte" => m("scalar", "Less than or equal to"),
          "lt" => m("scalar", "Less than"),
          "format" => m("string", ~s(The date format of the bounds, as "yyyy-MM-dd")),
          "time_zone" => "time_zone",
          "relation" => %{enum: ~w(INTERSECTS CONTAINS WITHIN)},
          "boost" => "number",
          "_name" => "string"
        }
      },
      "prefix_value" => %{
        one_of: [
          "string",
          %{
            object: %{
              "value" => "string",
              "case_insensitive" => "boolean",
              "rewrite" => "string",
              "boost" => "number"
            }
          }
        ]
      },
      "wildcard_value" => %{
        one_of: [
          "string",
          %{
            object: %{
              "value" => m("string", "A pattern: * any characters, ? one"),
              "wildcard" => "string",
              "case_insensitive" => "boolean",
              "rewrite" => "string",
              "boost" => "number"
            }
          }
        ]
      },
      "regexp_value" => %{
        one_of: [
          "string",
          %{
            object: %{
              "value" => "string",
              "flags" => %{enum: ~w(ALL COMPLEMENT EMPTY INTERSECTION INTERVAL NONE)},
              "case_insensitive" => "boolean",
              "max_determinized_states" => "integer",
              "rewrite" => "string",
              "boost" => "number"
            }
          }
        ]
      },
      "fuzzy_value" => %{
        one_of: [
          "scalar",
          %{
            object: %{
              "value" => "scalar",
              "fuzziness" => %{one_of: [%{enum: ["AUTO", "0", "1", "2"]}, "integer"]},
              "max_expansions" => "integer",
              "prefix_length" => "integer",
              "transpositions" => "boolean",
              "rewrite" => "string",
              "boost" => "number"
            }
          }
        ]
      },
      "terms_set_value" => %{
        object: %{
          "terms" => %{array: "scalar"},
          "minimum_should_match_field" => %{field: @numeric},
          "minimum_should_match_script" => "script",
          "boost" => "number"
        }
      },
      "function_score" => %{
        object: %{
          "query" => "query",
          "functions" => %{array: "score_function"},
          "score_mode" => %{enum: ~w(multiply sum avg first max min)},
          "boost_mode" => %{enum: ~w(multiply replace sum avg max min)},
          "max_boost" => "number",
          "min_score" => "number",
          "boost" => "number",
          "weight" => "number",
          "field_value_factor" => "field_value_factor",
          "random_score" => "random_score",
          "script_score" => %{object: %{"script" => "script"}}
        }
      },
      "score_function" => %{
        object: %{
          "filter" => "query",
          "weight" => "number",
          "field_value_factor" => "field_value_factor",
          "random_score" => "random_score",
          "script_score" => %{object: %{"script" => "script"}},
          "gauss" => "decay",
          "linear" => "decay",
          "exp" => "decay"
        }
      },
      "field_value_factor" => %{
        object: %{
          "field" => %{field: @numeric},
          "factor" => "number",
          "modifier" => %{enum: ~w(none log log1p log2p ln ln1p ln2p square sqrt reciprocal)},
          "missing" => "number"
        }
      },
      "random_score" => %{object: %{"seed" => "integer", "field" => "field"}},
      "decay" => %{
        object: %{"multi_value_mode" => %{enum: ~w(min max avg sum)}},
        fields: %{
          object: %{
            "origin" => "scalar",
            "scale" => "scalar",
            "offset" => "scalar",
            "decay" => "number"
          }
        }
      },
      "geo_distance" => %{
        object: %{
          "distance" => m("string", ~s(As "10km")),
          "distance_type" => %{enum: ["arc", "plane"]},
          "validation_method" => %{enum: ~w(STRICT IGNORE_MALFORMED COERCE)},
          "_name" => "string"
        },
        fields: "any"
      },
      "geo_bounding_box" => %{
        object: %{"validation_method" => %{enum: ~w(STRICT IGNORE_MALFORMED COERCE)}},
        fields: %{
          object: %{
            "top_left" => "any",
            "bottom_right" => "any",
            "top_right" => "any",
            "bottom_left" => "any",
            "wkt" => "string"
          }
        }
      },
      "more_like_this" => %{
        object: %{
          "fields" => %{array: "field"},
          "like" => "any",
          "unlike" => "any",
          "min_term_freq" => "integer",
          "max_query_terms" => "integer",
          "min_doc_freq" => "integer",
          "minimum_should_match" => %{one_of: ["integer", "string"]},
          "boost" => "number"
        }
      },
      "time_zone" => %{
        enum: ~w(UTC +00:00 +01:00 +02:00 -05:00 -08:00 Europe/Lisbon America/New_York)
      },
      "scalar" => %{one_of: ["string", "number", "boolean"]}
    }
  end

  defp query_clauses do
    %{
      "bool" =>
        m(
          "bool",
          "Combine clauses with must, filter, should and must_not",
          ~s({ "must": [ ${} ] })
        ),
      "match_all" => m(%{object: %{"boost" => "number"}}, "Every document", "{}"),
      "match_none" => m(%{object: %{}}, "No document", "{}"),
      "match" =>
        fields("match_value", "Full-text search on a field", ~s({ "${field}": "${text}" })),
      "match_phrase" =>
        fields(
          "match_phrase_value",
          "The words of a phrase, in order",
          ~s({ "${field}": "${phrase}" })
        ),
      "match_phrase_prefix" =>
        fields(
          "match_phrase_value",
          "A phrase, the last word as a prefix",
          ~s({ "${field}": "${text}" })
        ),
      "match_bool_prefix" =>
        fields("match_value", "Words, the last as a prefix", ~s({ "${field}": "${text}" })),
      "multi_match" =>
        m(
          "multi_match",
          "Full-text search on several fields",
          ~s({ "query": "${text}", "fields": [ "${}" ] })
        ),
      "combined_fields" => m("combined_fields", "Full-text search across fields as one"),
      "query_string" => m("query_string", "Lucene query syntax", ~s({ "query": "${}" })),
      "simple_query_string" =>
        m("simple_query_string", "Simple query syntax, never fails", ~s({ "query": "${}" })),
      "term" =>
        fields(
          "term_value",
          "An exact value (keyword, number, date…)",
          ~s({ "${field}": "${value}" })
        ),
      "terms" =>
        m(
          %{object: %{"boost" => "number", "_name" => "string"}, fields: %{array: "scalar"}},
          "Any of these exact values",
          ~s({ "${field}": [ ${} ] })
        ),
      "terms_set" => fields("terms_set_value", "A number of these values"),
      "range" =>
        fields("range_value", "A range of numbers or dates", ~s({ "${field}": { "gte": ${} } })),
      "exists" =>
        m(
          %{object: %{"field" => "field", "boost" => "number"}},
          "The field has a value",
          ~s({ "field": "${}" })
        ),
      "prefix" =>
        fields("prefix_value", "A value that starts with this", ~s({ "${field}": "${prefix}" })),
      "wildcard" =>
        fields(
          "wildcard_value",
          "A pattern with * and ?",
          ~s({ "${field}": { "value": "${*}" } })
        ),
      "regexp" => fields("regexp_value", "A regular expression", ~s({ "${field}": "${}" })),
      "fuzzy" => fields("fuzzy_value", "Values close to this one"),
      "ids" =>
        m(
          %{object: %{"values" => %{array: "string"}}},
          "Documents by id",
          ~s({ "values": [ "${}" ] })
        ),
      "constant_score" =>
        m(
          %{object: %{"filter" => "query", "boost" => "number"}},
          "A filter, every hit scored alike"
        ),
      "dis_max" =>
        m(
          %{
            object: %{
              "queries" => %{array: "query"},
              "tie_breaker" => "number",
              "boost" => "number"
            }
          },
          "The best of several clauses"
        ),
      "boosting" =>
        m(
          %{
            object: %{"positive" => "query", "negative" => "query", "negative_boost" => "number"}
          },
          "Lower the score of some matches"
        ),
      "function_score" => m("function_score", "Change scores with functions"),
      "script_score" =>
        m(
          %{object: %{"query" => "query", "script" => "script", "min_score" => "number"}},
          "Score with a script"
        ),
      "script" =>
        m(%{object: %{"script" => "script", "boost" => "number"}}, "Filter with a script"),
      "nested" =>
        m(
          %{
            object: %{
              "path" => %{field: ["nested"]},
              "query" => "query",
              "score_mode" => %{enum: ~w(avg max min none sum)},
              "ignore_unmapped" => "boolean",
              "inner_hits" => "inner_hits"
            }
          },
          "Search nested objects",
          ~s({ "path": "${}", "query": { } })
        ),
      "has_child" =>
        m(
          %{
            object: %{
              "type" => "string",
              "query" => "query",
              "score_mode" => %{enum: ~w(none avg sum max min)},
              "min_children" => "integer",
              "max_children" => "integer",
              "ignore_unmapped" => "boolean",
              "inner_hits" => "inner_hits"
            }
          },
          "Parents whose children match"
        ),
      "has_parent" =>
        m(
          %{
            object: %{
              "parent_type" => "string",
              "query" => "query",
              "score" => "boolean",
              "ignore_unmapped" => "boolean",
              "inner_hits" => "inner_hits"
            }
          },
          "Children whose parent matches"
        ),
      "geo_distance" => m("geo_distance", "Points within a distance"),
      "geo_bounding_box" => m("geo_bounding_box", "Points within a box"),
      "more_like_this" => m("more_like_this", "Documents like these"),
      "knn" => m("knn", "Nearest neighbours of a vector")
    }
  end

  # ---------------------------------------------------------------------------
  # Aggregations
  # ---------------------------------------------------------------------------

  defp aggregation_types do
    metric = fn types -> %{object: metric_keys(types)} end

    %{
      "aggs" => %{object: %{}, names: "agg"},
      "agg" => %{object: Map.merge(agg_kinds(metric), agg_extras())},
      "agg_order" => %{
        one_of: [
          %{object: %{"_count" => "sort_order", "_key" => "sort_order"}, names: "sort_order"},
          %{
            array: %{
              object: %{"_count" => "sort_order", "_key" => "sort_order"},
              names: "sort_order"
            }
          }
        ]
      },
      "bounds" => %{object: %{"min" => "scalar", "max" => "scalar"}},
      "agg_range" => %{object: %{"from" => "scalar", "to" => "scalar", "key" => "string"}},
      "composite_source" => %{
        object: %{},
        names: %{
          object: %{
            "terms" => %{
              object: %{
                "field" => %{field: @keywords},
                "order" => "sort_order",
                "missing_bucket" => "boolean"
              }
            },
            "histogram" => %{object: %{"field" => %{field: @numeric}, "interval" => "number"}},
            "date_histogram" => %{
              object: %{
                "field" => %{field: @dates},
                "calendar_interval" => "calendar_interval",
                "fixed_interval" => "string",
                "format" => "string",
                "time_zone" => "time_zone"
              }
            }
          },
          one_key: true
        }
      },
      "calendar_interval" => %{
        enum: ~w(minute hour day week month quarter year 1m 1h 1d 1w 1M 1q 1y)
      }
    }
  end

  defp agg_kinds(metric) do
    %{
      "terms" =>
        m(
          %{
            object: %{
              "field" => %{field: @keywords},
              "size" => "integer",
              "min_doc_count" => "integer",
              "shard_size" => "integer",
              "order" => "agg_order",
              "missing" => "scalar",
              "include" => "any",
              "exclude" => "any",
              "execution_hint" => %{enum: ["map", "global_ordinals"]},
              "show_term_doc_count_error" => "boolean",
              "script" => "script"
            }
          },
          "A bucket per value of a field",
          ~s({ "field": "${}", "size": 10 })
        ),
      "date_histogram" =>
        m(
          %{
            object: %{
              "field" => %{field: @dates},
              "calendar_interval" => "calendar_interval",
              "fixed_interval" => m("string", ~s(As "30m" or "12h")),
              "format" => "string",
              "time_zone" => "time_zone",
              "offset" => "string",
              "min_doc_count" => "integer",
              "extended_bounds" => "bounds",
              "hard_bounds" => "bounds",
              "order" => "agg_order",
              "keyed" => "boolean",
              "missing" => "scalar"
            }
          },
          "A bucket per interval of a date field",
          ~s({ "field": "${}", "calendar_interval": "${day}" })
        ),
      "auto_date_histogram" =>
        m(
          %{
            object: %{
              "field" => %{field: @dates},
              "buckets" => "integer",
              "format" => "string",
              "time_zone" => "time_zone",
              "minimum_interval" => %{enum: ~w(second minute hour day month year)}
            }
          },
          "Date buckets, the interval chosen for you"
        ),
      "histogram" =>
        m(
          %{
            object: %{
              "field" => %{field: @numeric},
              "interval" => "number",
              "offset" => "number",
              "min_doc_count" => "integer",
              "extended_bounds" => "bounds",
              "hard_bounds" => "bounds",
              "order" => "agg_order",
              "keyed" => "boolean",
              "missing" => "number"
            }
          },
          "A bucket per interval of a number",
          ~s({ "field": "${}", "interval": ${10} })
        ),
      "range" =>
        m(
          %{
            object: %{
              "field" => %{field: @numeric ++ @dates},
              "ranges" => %{array: "agg_range"},
              "keyed" => "boolean",
              "script" => "script"
            }
          },
          "A bucket per range",
          ~s({ "field": "${}", "ranges": [ { "to": ${} } ] })
        ),
      "date_range" =>
        m(
          %{
            object: %{
              "field" => %{field: @dates},
              "ranges" => %{array: "agg_range"},
              "format" => "string",
              "time_zone" => "time_zone",
              "keyed" => "boolean",
              "missing" => "string"
            }
          },
          "A bucket per date range"
        ),
      "filter" => m("query", "One bucket: the documents that match", "{ ${} }"),
      "filters" =>
        m(
          %{
            object: %{
              "filters" => %{one_of: [%{object: %{}, names: "query"}, %{array: "query"}]},
              "other_bucket" => "boolean",
              "other_bucket_key" => "string"
            }
          },
          "A bucket per filter"
        ),
      "missing" =>
        m(%{object: %{"field" => "field"}}, "A bucket for documents without the field"),
      "nested" => m(%{object: %{"path" => %{field: ["nested"]}}}, "Aggregate nested objects"),
      "reverse_nested" =>
        m(%{object: %{"path" => %{field: ["nested"]}}}, "Back to the parent documents"),
      "composite" =>
        m(
          %{
            object: %{
              "sources" => %{array: "composite_source"},
              "size" => "integer",
              "after" => %{object: %{}, open: true}
            }
          },
          "Pages of buckets over several fields"
        ),
      "significant_terms" =>
        m(
          %{object: %{"field" => %{field: @keywords}, "size" => "integer"}},
          "Unusually common values"
        ),
      "rare_terms" =>
        m(
          %{object: %{"field" => %{field: @keywords}, "max_doc_count" => "integer"}},
          "Rare values"
        ),
      "sampler" => m(%{object: %{"shard_size" => "integer"}}, "Aggregate a sample"),
      "avg" => m(metric.(@numeric), "Average", ~s({ "field": "${}" })),
      "sum" => m(metric.(@numeric), "Sum", ~s({ "field": "${}" })),
      "min" => m(metric.(@numeric ++ @dates), "Minimum", ~s({ "field": "${}" })),
      "max" => m(metric.(@numeric ++ @dates), "Maximum", ~s({ "field": "${}" })),
      "stats" => m(metric.(@numeric), "Count, min, max, avg and sum", ~s({ "field": "${}" })),
      "extended_stats" =>
        m(
          %{object: Map.put(metric_keys(@numeric), "sigma", "number")},
          "Stats, variance and deviation"
        ),
      "value_count" => m(metric.([]), "How many values", ~s({ "field": "${}" })),
      "cardinality" =>
        m(
          %{object: Map.put(metric_keys(@keywords), "precision_threshold", "integer")},
          "How many distinct values, approximately",
          ~s({ "field": "${}" })
        ),
      "percentiles" =>
        m(
          %{
            object:
              Map.merge(metric_keys(@numeric), %{
                "percents" => %{array: "number"},
                "keyed" => "boolean"
              })
          },
          "Percentiles",
          ~s({ "field": "${}", "percents": [ 50, 95, 99 ] })
        ),
      "percentile_ranks" =>
        m(
          %{
            object:
              Map.merge(metric_keys(@numeric), %{
                "values" => %{array: "number"},
                "keyed" => "boolean"
              })
          },
          "The percentile of these values"
        ),
      "top_hits" =>
        m(
          %{
            object: %{
              "size" => "integer",
              "from" => "integer",
              "sort" => "sort",
              "_source" => "source_filter",
              "highlight" => "highlight"
            }
          },
          "The top documents of each bucket",
          ~s({ "size": ${3} })
        ),
      "bucket_sort" =>
        m(
          %{object: %{"sort" => "sort", "from" => "integer", "size" => "integer"}},
          "Sort and page buckets"
        ),
      "bucket_selector" =>
        m(
          %{object: %{"buckets_path" => %{object: %{}, names: "string"}, "script" => "script"}},
          "Keep the buckets a script selects"
        ),
      "avg_bucket" => m(pipeline(), "Average of a metric across buckets"),
      "sum_bucket" => m(pipeline(), "Sum of a metric across buckets"),
      "max_bucket" => m(pipeline(), "Bucket with the highest metric"),
      "min_bucket" => m(pipeline(), "Bucket with the lowest metric"),
      "derivative" => m(pipeline(), "Change from the previous bucket"),
      "cumulative_sum" => m(pipeline(), "Running total across buckets")
    }
  end

  defp agg_extras do
    %{
      "aggs" => m("aggs", "Aggregations in each bucket", "{ ${} }"),
      "aggregations" => m("aggs", "Aggregations in each bucket", "{ ${} }"),
      "meta" => m(%{object: %{}, open: true}, "Data returned with the result")
    }
  end

  defp metric_keys(types) do
    %{
      "field" => %{field: types},
      "missing" => "scalar",
      "script" => "script",
      "format" => "string"
    }
  end

  defp pipeline do
    %{
      object: %{
        "buckets_path" => m("string", ~s(As "by_month>sales")),
        "gap_policy" => %{enum: ~w(skip insert_zeros keep_values)},
        "format" => "string"
      }
    }
  end

  # A member: its type, what it does, and what to insert after its key.
  defp m(type, doc, snippet \\ nil)
  defp m(type, doc, nil), do: %{type: type, doc: doc}
  defp m(type, doc, snippet), do: %{type: type, doc: doc, snippet: snippet}

  # A query clause keyed by a field: `{"term": {"status": ...}}`.
  defp fields(value, doc, snippet \\ nil),
    do: m(%{object: %{}, fields: value}, doc, snippet)
end
