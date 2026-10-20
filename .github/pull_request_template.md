## Why

<!-- The problem this solves, for whom, and what happened before it (an error, a wrong result, a query the cluster rejected). -->

Fixes #<!-- the issue; see CONTRIBUTING.md for when a pull request needs one -->

## What

<!-- The change, in a few lines. -->

## How it was tested

<!-- The tests added, and what you ran by hand: against Elasticsearch or OpenSearch, and which version. -->

## Checklist

- [ ] One change: anything unrelated is in its own pull request.
- [ ] A bug fix has a test that fails on `main` and passes here.
- [ ] `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict` and `mix test` (with the cluster from `mix test.setup`) pass.
- [ ] The README or `guides/writing-queries.md`, and an `## [Unreleased]` entry in `CHANGELOG.md`, are updated, for a change a user can see.
- [ ] Says so here if it changes the public API, the config shape or what the adapter sends to the cluster.
- [ ] No changes to the version in `mix.exs` or the changelog's release headings (the maintainers keep those).
