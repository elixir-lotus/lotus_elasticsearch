# Lotus Elasticsearch

**Elasticsearch and OpenSearch source adapter for [Lotus](https://github.com/elixir-lotus/lotus).** Run Lotus queries, dashboards, and AI-assisted exploration against an Elasticsearch cluster the same way you would against Postgres, MySQL, or SQLite.

A Lotus statement here is an Elasticsearch Query DSL JSON object rather than SQL text. Variables, optional clauses, filters, sorts and pagination all rewrite that object structurally — see [Writing Queries](guides/writing-queries.md).

> **0.1.0 — first release.** The adapter is complete against the Lotus v1 `Lotus.Source.Adapter` contract and its test suite runs against a live cluster, but its own surface — the client macro, the config shape, the index and field mapping, the type mapping — has no production users yet and may still move. Pin accordingly.

## Installation

Add both `lotus` and `lotus_elasticsearch` to your `mix.exs`:

```elixir
def deps do
  [
    {:lotus, "~> 1.0"},
    {:lotus_elasticsearch, "~> 0.1"}
  ]
end
```

Requires Elixir 1.18 or later. CI runs the suite on Elixir 1.18, 1.19 and 1.20 against OpenSearch 2.18.

## Configuring a data source

There are two ways to put an Elasticsearch cluster into `:data_sources`. They are **alternatives** — pick one per source, not both. Both work because `can_handle?/1` claims two kinds of entry: an atom that is a module exporting `__elasticsearch__/0`, and a map with `adapter: :elasticsearch`.

### Option A — a client module

Define a module with the `Lotus.Elasticsearch` macro and let it read its connection settings from your application config:

```elixir
defmodule MyApp.SearchClient do
  use Lotus.Elasticsearch, otp_app: :my_app
end
```

```elixir
config :my_app, MyApp.SearchClient,
  url: "http://localhost:9200",
  username: "elastic",
  password: "changeme"

config :lotus,
  source_adapters: [Lotus.Source.Adapters.Elasticsearch],
  data_sources: %{
    "postgres" => MyApp.Repo,
    "search"   => MyApp.SearchClient
  }
```

The macro defines exactly three functions on your module: `__elasticsearch__/0` (the marker `can_handle?/1` looks for), `config/0` (reads `Application.get_env(otp_app, __MODULE__, [])`), and `url/0`. `wrap/2` calls `config/0` and reads `:url`, `:username` and `:password` out of it.

**Pick this when** your connection settings come from `config/runtime.exs` and environment variables, or when you want one named module to refer to the cluster from elsewhere in your app. Application config is evaluated at runtime on every `config/0` call, so a secret does not have to be baked into the `:lotus` config map.

### Option B — an inline config map

```elixir
config :lotus,
  source_adapters: [Lotus.Source.Adapters.Elasticsearch],
  data_sources: %{
    "postgres" => MyApp.Repo,
    "search"   => %{
      adapter: :elasticsearch,
      url: "http://localhost:9200",
      username: "elastic",
      password: "changeme",
      allow_unrestricted_resources: true
    }
  }
```

**Pick this when** you want everything about the source in one place, and especially when you want the per-source `allow_unrestricted_resources` opt-in described under [Visibility](#visibility) — Lotus reads that key off the `:data_sources` entry itself, so it is only available on the map form. With Option A your only lever is the global flag.

#### Why `:elasticsearch` and not the adapter module

Lotus's canonical map form is `%{adapter: SomeModule, ...}`, which is used directly with no probing. The bare `:elasticsearch` atom here is deliberate and is *not* that form: core distinguishes the two by whether the atom is `Elixir.`-prefixed, and a non-prefixed atom is treated as the host application's own discriminator. The entry therefore falls through to `can_handle?/1` probing, which is why **`:source_adapters` must list `Lotus.Source.Adapters.Elasticsearch` for either option to resolve.**

If you prefer the no-probing path, `%{adapter: Lotus.Source.Adapters.Elasticsearch, url: ...}` also works and lets you drop the `:source_adapters` entry — `wrap/2` reads the same `:url` / `:username` / `:password` keys either way.

## Running a query

```elixir
{:ok, result} =
  Lotus.run_statement(
    ~s|{"query": {"term": {"status": "active"}}, "size": 10}|,
    [],
    repo: "search",
    index: "users"
  )
```

`:index` is an adapter-specific option that Lotus passes through untouched to `execute_query/4`; it becomes the index path segment of the `_search` call. **It defaults to `"_all"`**, which searches every index in the cluster — almost never what you want, so pass it explicitly.

Two consequences worth knowing before you build on this:

- `Lotus.Storage.Query` has no column for the index. A saved query carries its statement, data source, search path and variables; the index has to be supplied as a run-time option on each `Lotus.run_query/2` call.
- Lotus's result cache key is built from the statement body, bound variables, source name, search path and scope. `:index` is not part of it, so the same body run against two indices shares a cache entry. Use `cache: :bypass` or distinct statements if that matters to you.

## What works

- **Query execution** against `_search`, with `_source` fields plus `_id` and `_index` flattened into columns. Object and array values are JSON-encoded into the cell.
- **Filters, sorts and pagination** rewrite the query body rather than wrapping it in SQL-shaped subqueries: filters become `bool.filter` clauses (`term`, `terms`, `range`, `wildcard`, `exists`), sorts become a `sort` array, pagination becomes `from`/`size`. Supported filter operators are `:eq`, `:neq`, `:gt`, `:gte`, `:lt`, `:lte`, `:like`, `:is_null`, `:is_not_null`, `:in`; core raises `Lotus.UnsupportedOperatorError` on anything else rather than degrading silently.
- **`{{var}}` substitution** with JSON-literal escaping. This is the adapter's injection boundary: the value is run through `Lotus.JSON.encode!/1` and the encoded literal replaces the marker, so a string stays a quoted JSON string, a number or boolean sheds its quotes, and a list becomes a JSON array. `[[ ... ]]` optional clauses work too, on the raw text before parsing. See [Writing Queries](guides/writing-queries.md) for the rules — in particular that every `{{var}}` must sit inside JSON string quotes.
- **Exact counts in one round-trip.** When the caller asks for `count: :exact`, `apply_pagination/3` adds `"track_total_hits": true` to the body and `execute_query/4` reads `hits.total.value` back out — Lotus core's "Strategy A", so there is no second count query. Without that flag the adapter deliberately reports no total, because Elasticsearch caps its default estimate at 10 000 and returns a `gte` relation that is not a trustworthy number.
- **Schema introspection** — `_cat/indices` lists indices (dot-prefixed system indices are filtered out), `_mapping` describes an index's fields. Every field is reported as nullable with no default, and `_id` is flagged as the primary key. `list_schemas/1` returns `[]` and the hierarchy label is `"Indices"`: Elasticsearch has no namespace level above the index.
- **Pre-execution validation.** `validate_statement/3` strips `[[ ]]` blocks, neutralizes unbound `{{var}}` markers to `null`, and posts the body to `_validate/query?explain=false`.
- **AI integration** — `ai_context/1` declares the `json:elasticsearch` language, an example query, error-pattern hints for `index_not_found_exception` / `mapper_parsing_exception` / `parsing_exception`, and `generation`, `optimization` and `explanation` all enabled. Note that syntax notes and error patterns only reach the LLM prompt if you also list the adapter in `config :lotus, :trusted_source_adapters`; otherwise core strips everything but `:language`.
- **Editor support** — `Lotus.Source.Adapters.Elasticsearch.EditorConfig` supplies the query DSL vocabulary and a `:context_schema` that drives structure-aware autocomplete in `lotus_web`.
- **Identifier validation** matching Elasticsearch's own rules: index names lowercase, non-empty, at most 255 bytes, no leading `-` `_` `+`, none of `\ / * ? " < > | , # :` or whitespace; field names with no control characters, no leading or trailing whitespace, and no leading or trailing dot — dots *inside* a field name are legal, because they are nested field paths. `parse_qualified_name/2` likewise does not split on dots, since `app.logs.2025-01` is one index name.

## What this adapter cannot do

Being explicit about the SQL-shaped things that are absent:

- **No query plan.** `query_plan/3` returns `{:ok, nil}`. Elasticsearch has no plan source that is cheap, useful and production-safe at once: the Profile API carries real runtime overhead, `_search?explain` is scoring-only, and `_validate?explain=true` reveals nothing the statement and the mapping do not already. The AI optimizer works from the statement and `describe_table/3` output instead.
- **No query-populated variable dropdowns.** `supports_feature?/2` answers `true` for `:json` and `:arrays` and `false` for everything else, `:dynamic_options` included — a search returns shaped documents rather than a flat column of values, so the UI asks for dropdown options by hand. It is also `false` for `:schema_hierarchy`, `:search_path` and `:make_interval`, none of which mean anything here.
- **No static visibility analysis.** See below.
- **No transactions.** `transaction/3` runs the function and returns its value; there is nothing to roll back.
- **No connection pooling or supervision.** Each call is a one-shot `Req` HTTP request against the configured URL. `disconnect/1` is a no-op.
- **Aggregation results do not currently reach the result table.** The adapter has a path that turns bucket aggregations into rows (one row per bucket) and metric aggregations into a single row, but a real `_search` response carries `hits.total` even when `"size": 0`, and the hits branch claims the response first. Treat aggregations as unsupported in 0.1.0.

## Visibility

Unlike SQL adapters, where Lotus can statically parse which tables a statement touches, Elasticsearch queries name their indices in the HTTP path, not the JSON body. `extract_accessed_resources/2` therefore returns `{:unrestricted, reason}`, and `needs_preflight?/2` is always `true` — so **out of the box every query against this source is blocked by preflight**, with an error telling you how to opt in.

Opt in for the one source, on the map form:

```elixir
config :lotus,
  data_sources: %{
    "search" => %{adapter: :elasticsearch, url: "...", allow_unrestricted_resources: true}
  }
```

or globally, which is the only option if you configured the source as a client module:

```elixir
config :lotus, :allow_unrestricted_resources, true
```

The per-source value wins over the global flag in both directions. Opting in means you are trusting Elasticsearch's own index-level security to enforce who can read what — Lotus stops asking.

`builtin_denies/1` does still hide dot-prefixed system indices (`.kibana`, `.security`, …) from the schema explorer and table-level deny checks. That is a listing rule, not an execution guard: it does not stop a statement whose `:index` option names one.

## Development

```bash
mix deps.get
mix test.setup   # docker compose up -d — OpenSearch on port 9209
mix test
```

Unit tests run without a cluster. The tests under `test/integration/` need the docker-compose cluster on `http://localhost:9209`; they create and tear down indices prefixed `lotus_test`.

## Guides

- [Writing Queries](guides/writing-queries.md) — the statement format, variables and optional clauses, and exactly how filters, sorts and pagination rewrite the query body.

## License

MIT — see [LICENSE](LICENSE).
