# Writing Queries

A Lotus statement for an Elasticsearch source is an **Elasticsearch Query DSL JSON object** — the same body you would `POST` to `/<index>/_search` by hand. There is no SQL layer and no translation step: what you write is what the cluster receives, plus whatever Lotus's pipeline adds on the way through.

This guide covers what that pipeline adds, in the order it happens.

## The statement

```json
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "status": "active" } },
        { "range": { "age": { "gte": 18 } } }
      ]
    }
  },
  "sort": [{ "created_at": { "order": "desc" } }],
  "size": 100
}
```

Lotus stores that as text and hands it to the adapter. The adapter's first act on any path is `ensure_map/1`, which decodes the text into a map — a JSON value that is not an object is rejected ("Query must be a JSON object"), and unparseable text is rejected with `Invalid JSON: ...`. From that point on, every pipeline callback operates on the decoded map, and `Lotus.Query.Statement`'s `:body` holds a map rather than a string. Core never inspects it; `:body` is typed `term()` precisely so adapters like this one can carry a structure instead of text.

The index is **not** part of the statement. It travels as the `:index` run-time option and becomes the path segment of the `_search` request. It defaults to `"_all"`.

```elixir
Lotus.run_statement(body, [], repo: "search", index: "orders")
```

Because `:params` is never used — values are inlined into the body — the adapter always leaves it `[]`.

## Variables

Lotus's `{{var_name}}` syntax works, with one rule that has no SQL equivalent.

### Every `{{var}}` must sit inside JSON string quotes

Variables are substituted one at a time, and each substitution round-trips the body through JSON. A template is only parseable if it is valid JSON *before* any value is bound, so a bare `{{min_age}}` in value position would make the template unparseable. Write it quoted:

```json
{ "query": { "range": { "age": { "gte": "{{min_age}}" } } } }
```

### Substitution inlines a JSON literal

`substitute_variable/5` encodes the value with `Lotus.JSON.encode!/1` and splices the encoded literal in. It replaces `"{{var}}"` — marker *including* the surrounding quotes — before it replaces a bare `{{var}}`, which is how a quoted placeholder ends up holding a non-string value:

| Template fragment | Value | Result |
|---|---|---|
| `{"term": {"status": "{{status}}"}}` | `"active"` | `{"term": {"status": "active"}}` |
| `{"range": {"age": {"gte": "{{min_age}}"}}}` | `18` | `{"range": {"age": {"gte": 18}}}` |
| `{"term": {"active": "{{flag}}"}}` | `true` | `{"term": {"active": true}}` |
| `{"terms": {"tag": "{{tags}}"}}` | `["a", "b"]` | `{"terms": {"tag": ["a", "b"]}}` |

List variables take the same path — `substitute_list_variable/5` delegates to `substitute_variable/5`, and `supports_feature?(state, :arrays)` is `true`, so a list binds as one JSON array rather than being expanded into N placeholders.

### This is the injection boundary

Lotus's adapter contract makes `substitute_variable/5` the one place an adapter is responsible for injection safety, and JSON encoding is what does the work here. A user-supplied string containing `"`, `}`, or a whole nested object is encoded as a JSON *string literal* — quotes escaped, structure inert — so it lands in the body as data. It cannot grow the query into new clauses the way a naive SQL string concatenation can.

What it does **not** do is constrain *which* field a value is compared against, or which index is searched. Field names in the template are yours; the `:index` option is the caller's.

A marker whose variable is not being substituted on this pass is left exactly as it is, so a body with several variables survives the fold intact.

### Optional clauses

`[[ ... ]]` blocks work, because Lotus applies them to the raw statement text before the adapter ever sees it — a block whose variables have no value (missing, `nil`, or `""`) is dropped entirely; otherwise the brackets are removed and the content kept. Since this is a plain text operation, the block has to be written so that both outcomes leave valid JSON. In practice that means bracketing a whole array element, comma included:

```json
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "status": "{{status}}" } }
        [[, { "range": { "age": { "gte": "{{min_age}}" } } }]]
      ]
    }
  }
}
```

With `min_age` supplied, the second clause stays. Without it, the block vanishes and the array is still well-formed.

`validate_statement/3` and `prepare_for_analysis/2` both inspect a statement without binding values, so they strip the brackets unconditionally and neutralize every remaining `{{var}}` to `null` — the JSON-native analogue of SQL's `NULL` — before parsing.

## How the pipeline rewrites the body

Lotus's runner applies filters, then sorts, then pagination, each as a `statement -> statement` transform. For a SQL adapter those steps wrap the query in subqueries or CTEs. Here they edit the DSL structurally.

### Filters

Result-table filters are converted to DSL clauses and appended to the query's `bool.filter` array — filter context, so they are cacheable and do not affect scoring.

| Lotus operator | Clause |
|---|---|
| `:eq` | `{"term": {field: value}}` |
| `:neq` | `{"bool": {"must_not": [{"term": {field: value}}]}}` |
| `:gt` / `:gte` / `:lt` / `:lte` | `{"range": {field: {"gt": value}}}` (etc.) |
| `:like` | `{"wildcard": {field: {"value": "*value*"}}}` |
| `:in` | `{"terms": {field: values}}` |
| `:is_null` | `{"bool": {"must_not": [{"exists": {"field": field}}]}}` |
| `:is_not_null` | `{"exists": {"field": field}}` |

Those ten are exactly what `supported_filter_operators/1` declares. Core validates the caller's operators against that list up front and raises `Lotus.UnsupportedOperatorError` on anything outside it, rather than dropping the filter silently.

How the clauses are attached depends on what the body already has:

- If `query` is already a `bool`, the new clauses are **appended to its existing `filter` array**. Anything in `must`, `should` or `must_not` is untouched.
- Otherwise the existing query is moved into `must` and the new clauses go into `filter` of a fresh `bool`:

  ```json
  { "query": { "bool": {
      "must":   [ <your original query> ],
      "filter": [ <the new clauses> ]
  } } }
  ```

- If the body has no `query` key at all, `{"match_all": {}}` is used as the original.

An empty filter list is a no-op — the body is returned unchanged.

Because these are `term`-family clauses, they run against the field exactly as named. Filtering an analyzed `text` field with `:eq` will usually match nothing; point it at the `.keyword` subfield instead.

### Sorts

Sorts **replace** the body's `sort` key outright — they do not merge with a `sort` you wrote by hand:

```json
"sort": [ { "created_at": { "order": "desc" } }, { "status": { "order": "asc" } } ]
```

An empty sort list leaves the body alone, so a hand-written `sort` survives as long as the caller adds none.

### Pagination

`apply_pagination/3` merges `from` (the offset, default `0`) and `size` (the limit) into the top level of the body, overwriting any `from`/`size` you wrote. Deep offsets hit Elasticsearch's own `index.max_result_window` ceiling — around 10 000 by default — and the adapter does nothing to work around that; `search_after` is the cluster-side answer and is not wired into Lotus's window contract.

### Exact counts

When the caller asks for `count: :exact`, pagination also sets `"track_total_hits": true`, and `execute_query/4` reads the total back out of `hits.total.value` on the same response. This is Lotus core's "Strategy A": the count comes back with the data, so no `:count_spec` is placed in `statement.meta` and core runs no second query.

The total is only surfaced when both halves agree — the body asked for `track_total_hits` **and** the response reports `"relation": "eq"`. With `count: :none` (the default), nothing is set and no total is reported at all. That is deliberate: Elasticsearch's untracked default caps the number it reports at 10 000 and marks it `gte`, and reporting that as a row count would be a lie.

## What comes back as rows

`execute_query/4` flattens the response into `%{columns: [...], rows: [...], num_rows: n}`, optionally with `:total_count`.

For each hit, `_source` is taken as the document, then `_id` and `_index` are added as fields. The column list is the **union of the keys across all hits in the page**, sorted alphabetically — so a document missing a field yields `nil` in that cell rather than shifting the row. Values that are maps or lists are JSON-encoded into the cell as text; scalars pass through.

This has a consequence worth planning around: two documents in the same index with different shapes produce a wide, sparse result. Use `_source` includes, or `fields`, to pin the shape you want.

An empty hit list gives `{[], []}` — no columns, no rows.

### Aggregations

Aggregations are **not usable in 0.1.0**. The adapter carries a conversion path — a bucket aggregation becomes one row per bucket with the bucket's keys as columns, and metric aggregations become a single row with one column per named aggregation, unwrapping `{"value": v}` — but a real `_search` response always carries `hits.total`, including when you set `"size": 0`, and the hits branch claims the response before the aggregation branch is reached. An aggregation query currently returns an empty result rather than its buckets.

## Validating before running

`validate_statement/3` posts the neutralized body to `/_validate/query?explain=false` and maps the response: `{"valid": true}` becomes `:ok`; `{"valid": false}` becomes an error built from the `explanations` array. `lotus_web`'s "validate before run" button and the AI `validate_statement` action both go through it.

Two caveats. The request is sent cluster-wide, not against the `:index` you intend to run on, so index-specific mapping problems will not be caught. And `_validate/query` accepts only a `query` key in its body — a statement that also carries `size`, `sort` or `aggs` may be rejected by Elasticsearch for the extra keys rather than for anything wrong with the query itself.

## Errors

Failures come back as strings shaped `Elasticsearch Error (<status>): <type>: <reason>`, read out of the response's `error.type` and `error.reason`. `ai_context/1` additionally ships hints keyed on three patterns, so the AI pipeline can react to them:

| Pattern | Hint |
|---|---|
| `index_not_found_exception` | The index does not exist — list the available ones. |
| `mapper_parsing_exception`, `illegal_argument_exception` | Field type mismatch or malformed query — check the mapping. |
| `parsing_exception` | The Query DSL is syntactically invalid. |

Those hints only reach the LLM prompt if you list the adapter in `config :lotus, :trusted_source_adapters`. Untrusted adapters have everything but `:language` stripped from their AI context.

## What the schema explorer shows

Elasticsearch has no namespace above the index, so `list_schemas/1` returns `[]`, `resolve_table_namespace/3` returns `nil`, `supports_feature?(state, :schema_hierarchy)` is `false`, and the UI labels the level `"Indices"`.

- **Indices** come from `/_cat/indices?format=json&h=index,health,docs.count`, with dot-prefixed system indices removed and the rest sorted. A failed request yields an empty list rather than an error, so an unreachable cluster shows as "no indices".
- **Fields** come from `/<index>/_mapping`, read out of `mappings.properties`. Each field is reported with its mapping `type` (or `"object"` when the mapping declares none), `nullable: true`, no default, and `primary_key: true` only for `_id`. Nothing in a mapping expresses nullability or defaults, so those two are constants rather than facts about your data.
- **Types** are mapped to Lotus's own vocabulary for display and variable typing: the string family (`text`, `keyword`, `constant_keyword`, `wildcard`, `ip`, `geo_point`, `geo_shape`) to `:text`; the integer family (`long`, `integer`, `short`, `byte`, `unsigned_long`) to `:integer`; `double`, `float` and `half_float` to `:float`; `scaled_float` to `:decimal`; `boolean` to `:boolean`; `date` and `date_nanos` to `:datetime`; `object`, `nested` and `flattened` to `:json`; `binary` to `:binary`. Anything unrecognized falls back to `:text`.

Note that the mapping is read one level deep. Sub-fields — the `.keyword` multi-field you will want for exact matching and sorting — are not listed, even though you can query them.

## Further reading

- [Lotus source adapters guide](https://github.com/elixir-lotus/lotus/blob/main/guides/source-adapters.md) — the statement contract, pipeline order, count strategies, and the security boundaries this adapter implements.
- [Lotus visibility guide](https://github.com/elixir-lotus/lotus/blob/main/guides/visibility.md) — `{:unrestricted, reason}` and `:allow_unrestricted_resources`.
