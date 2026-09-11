# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - Unreleased

First release. Requires Lotus `~> 1.0`.

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

[1.0.0]: https://github.com/elixir-lotus/lotus_elasticsearch/releases/tag/v1.0.0
