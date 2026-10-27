# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Breaking Changes

- **Requires Lotus v2.** Lotus v2 split the adapter behaviour into a core
  behaviour and capability behaviours, and calls a capability only when the
  adapter declares it. The adapter now declares
  `Lotus.Source.Adapter.Introspection`, `Preflight`, `Binding`, `Shaping`,
  `Editor`, `Connection` and `Cancel`, so it no longer compiles against
  Lotus 1.x. Until Lotus 2.0 is on Hex it depends on Lotus `main` from
  GitHub, as Lotus Web does. Use `0.2` with Lotus `~> 1.3`.

### Added

- **The shape of a search request, for the editor.** The editor config's
  `:context_schema` has a `:grammar`
  (`Lotus.Source.Adapters.Elasticsearch.EditorGrammar`): the keys of every
  object of a search request, what each takes (a query, a field and its
  mapping types, an index, one of a set of values, a number…), and a
  snippet to insert, with the queries, aggregations and parameters most
  used. Lotus Web completes from it at every level and warns about a key
  it does not know there. The flat `:root`, `:children` and
  `:value_literals` stay, for an editor that does not read it.
- **Fields by their path.** `describe_table/3` lists an object's and a
  nested field's own fields (`address.city`) and a field's multi-fields
  (`customer.keyword`) after it, with their types, where it listed the
  top-level fields only. The schema browser and the editor's completion
  show them.

- **Stop a running search.** `Lotus.cancel/1`, and Lotus Web's Stop button,
  cancel the search on the cluster: each search carries an `X-Opaque-Id`,
  and the adapter cancels the task with that header through the tasks API.
  `Lotus.cancellable?/1` is `true` for an Elasticsearch source.
- **A `{{var}}` can stand bare where a value goes**, as in `"size": {{n}}`
  or `"terms": {"tag": {{tags}}}`. It binds to the value's JSON literal, as
  `"{{n}}"` does.

- **A form that connects an Elasticsearch or OpenSearch source from the
  app.** With Lotus v2, `Lotus.Source.Connections.kinds/0` lists
  `"elasticsearch"` with a URL, user and password, so a host or Lotus Pro can
  let people connect a cluster without a client module in the config. A
  failed health check now reads as the cluster's error
  (`Elasticsearch Error (401): …`) rather than the raw response. Lotus v1
  ignores the form.

### Fixed

- **A `{{var}}` inside a longer string binds.** `"*{{q}}*"` raised a JSON
  decode error when the query ran; the value's text is now spliced into the
  string, escaped.
- **Validation reads variables and optional blocks as Lotus does.**
  `validate_statement/3` and `prepare_for_analysis/2` found `{{var}}` and
  `[[ ]]` with SQL's lexical rules, where `\"` ends a quoted name, so in
  `"say \"hi [[x]]\""` the brackets were stripped from the string. They now
  use the JSON profile of `Lotus.Query.Tokenizer`, as the rest of the
  pipeline does.

- **The `:index` option can only name indices.** It went into the request
  path unchecked, so a value such as `"x/_delete_by_query?q=*&"` reached
  another API than `_search` or `_mapping`, one that can write. A value
  with `/`, `\`, `?`, `#`, `%`, `"`, `<`, `>`, `|` or a space is now
  refused before any request, with an error that names it. Wildcards,
  lists, `_all` and remote clusters still pass; date math
  (`<logs-{now/d}>`) no longer does.

## [0.2.0] - 2026-10-17

The adapter reports index sizes, which Lotus 1.3's AI assistant and MCP
server show, and owns a Finch pool per source. Requires Lotus `~> 1.3`.

### Added

- **Index sizes for `table_row_estimates/2`.** Each index's document count
  comes from `_cat/indices` in one request. Lotus's `table_row_estimates/2`
  and the MCP server's `list_tables` (`approx_rows`) show it, so a model
  can tell large indices from small ones. The count includes nested
  documents, so it overestimates top-level documents. Closed and hidden
  indices are left out. This requires Lotus 1.3, which adds the callback
  (elixir-lotus/lotus#324).

- **One Finch per adapter with a pool per source URL.** The adapter
  implements the Lotus source lifecycle callbacks: `shared_children/0`
  starts `Lotus.Elasticsearch.Finch` once, and `source_started/2` adds a
  pool for the source URL with `Finch.start_pool/3` when the source starts,
  so sources added at runtime get their own pool. New source keys
  `pool_size`, `pool_count`, `connect_timeout` and `receive_timeout` size
  the pool and its timeouts; the `:timeout` query option overrides
  `receive_timeout` per request. Every request names the adapter's Finch
  when it is running and falls back to Req's default Finch otherwise, so
  nothing changes under a Lotus that does not supervise source lifecycles.

## [0.1.0] - 2026-09-12

First release. Requires Lotus `~> 1.0`.

This adapter was written while Lotus core was reworked to support non-SQL
data sources, and it is the reference implementation for a source whose
statements are not SQL text. It is complete against the v1 adapter contract
and its test suite runs against a live cluster, but its own surface — the
client macro, the configuration shape, the index and field mapping — has no
production users yet, so it starts at 0.1.0 rather than claiming a stable
API.

### Added

- `Lotus.Source.Adapters.Elasticsearch`, a source adapter for Elasticsearch
  and OpenSearch clusters. Statements carry the search body as a decoded JSON
  map rather than SQL text, so filters, sorts, pagination and variable
  substitution all rewrite the query DSL structurally.
- `use Lotus.Elasticsearch` to define a client module, with connection
  settings read from the host application's config.
- Index and mapping introspection, so the schema explorer lists indices and
  their fields the way it lists tables and columns for a SQL source.
- Editor support through `Lotus.Source.Adapters.Elasticsearch.EditorConfig`:
  query DSL keywords, field types, and a `:context_schema` that drives
  structure-aware autocomplete in the web editor.
- AI context declaring the `json:elasticsearch` language, an example query,
  syntax notes and error patterns, so query generation, optimization and
  explanation all work against Elasticsearch sources.
- Feature reporting through `supports_feature?/2`: JSON and arrays are
  supported. Query-populated variable dropdowns (`:dynamic_options`) are not,
  because a search returns shaped documents rather than a flat column of
  values, so the UI asks for dropdown options by hand.

### Notes

- `query_plan/3` returns `{:ok, nil}`. Elasticsearch has no plan source that
  is cheap, useful and production-safe at once: the Profile API carries real
  runtime overhead, `_search?explain` is scoring-only, and
  `_validate?explain=true` reveals nothing the statement and mapping do not.

[0.1.0]: https://github.com/elixir-lotus/lotus_elasticsearch/releases/tag/v0.1.0
