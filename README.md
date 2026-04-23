# Lotus Elasticsearch

**Elasticsearch and OpenSearch source adapter for [Lotus](https://github.com/elixir-lotus/lotus).** Run Lotus queries, dashboards, and AI-assisted exploration against an Elasticsearch cluster the same way you would against Postgres, MySQL, or SQLite.

## Installation

Add both `lotus` and `lotus_elasticsearch` to your `mix.exs`:

```elixir
def deps do
  [
    {:lotus, "~> 1.0"},
    {:lotus_elasticsearch, "~> 1.0"}
  ]
end
```

## Usage

Define a client module for your cluster:

```elixir
defmodule MyApp.SearchClient do
  use Lotus.Elasticsearch, otp_app: :my_app
end
```

Configure it:

```elixir
config :my_app, MyApp.SearchClient,
  url: "http://localhost:9200",
  username: "elastic",
  password: "changeme"
```

Register the adapter and add the client as a data source:

```elixir
config :lotus,
  source_adapters: [Lotus.Source.Adapters.Elasticsearch],
  data_sources: %{
    "postgres" => MyApp.Repo,
    "search"   => MyApp.SearchClient
  }
```

Run a query like any other Lotus source:

```elixir
{:ok, result} =
  Lotus.run_statement(
    ~s|{"query": {"term": {"status": "active"}}, "size": 10}|,
    [],
    repo: "search",
    index: "users"
  )
```

The full Lotus feature set works against Elasticsearch: dashboards, filters (mapped to DSL `term`/`range`/`wildcard` clauses), sorts, pagination (`from`/`size`), result-table filtering, CSV export, AI-assisted query generation with ES DSL syntax notes, and schema introspection (indices and field mappings).

## What's in the box

- Query execution against `_search`, including aggregations surfaced as tabular rows
- Filter, sort, and pagination callbacks that modify the query body rather than wrapping it in SQL-shaped CTEs
- `{{var_name}}` variable substitution with JSON-literal escaping (the primary injection boundary — see [`guides/source-adapters.md`](https://github.com/elixir-lotus/lotus/blob/main/guides/source-adapters.md) in the Lotus core repo)
- `track_total_hits: true` inline count strategy — `count: :exact` returns the full total in a single round-trip, no second query
- Schema introspection via `_cat/indices` and `_mapping`
- `validate_statement/3` via `_validate/query?explain=false` — pre-execute syntax checks
- Full `Lotus.AI` integration: generation, optimization, and explanation capabilities enabled, with ES-specific syntax notes (filter context vs query context, `term` on `.keyword` vs `match` on `text`, `search_after` for deep pagination, aggregation cardinality, `doc_values`)
- ES-native identifier validation (index names, field names — including dotted nested field paths)

## Visibility

Unlike SQL adapters where Lotus can statically parse which tables a statement touches, Elasticsearch queries target indices via the HTTP URL, not the JSON body. `extract_accessed_resources/2` therefore returns `{:unrestricted, reason}` — Lotus blocks execution by default. Opt in per-source when index-level security is enforced by ES cluster permissions:

```elixir
config :lotus,
  data_sources: %{
    "search" => %{adapter: :elasticsearch, url: "...", allow_unrestricted_resources: true}
  }
```

Or globally via `config :lotus, :allow_unrestricted_resources, true`.

## Development

```bash
mix deps.get
mix test.setup   # brings up Elasticsearch via docker compose
mix test
```

Unit tests run without Elasticsearch; integration tests in `test/integration/` require the docker-compose cluster to be running.

## License

MIT — see [LICENSE](LICENSE).
