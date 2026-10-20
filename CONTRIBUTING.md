# Contributing to Lotus Elasticsearch

Thank you for helping. This page says what to open (an issue, a pull
request, or a security report), what a pull request needs, and what the
maintainers keep for themselves. How to install the dependencies, start
the OpenSearch cluster the tests use and run them is in the README, under
[Development](README.md#development).

This repository is the Elasticsearch and OpenSearch source adapter. A
problem in Lotus itself belongs in
[elixir-lotus/lotus](https://github.com/elixir-lotus/lotus), and one in the
web UI in [elixir-lotus/lotus_web](https://github.com/elixir-lotus/lotus_web).
The Lotus
[contributing guide](https://github.com/elixir-lotus/lotus/blob/main/guides/contributing.md)
explains the `Lotus.Source.Adapter` contract this adapter implements.

## Questions, bugs and ideas

- **A bug.** Open an issue with the bug report form. The statement, the
  options it ran with (`:index` above all) and the error the cluster or
  the adapter returned are the most useful things you can give.
- **An idea or a change of behaviour.** Open an issue with the feature
  request form, and say the problem before the solution.
- **A security problem.** Do not open an issue. See
  [SECURITY.md](SECURITY.md).

Search the open and closed issues first: the idea may already be planned,
or turned down for a reason given there. The README's
[What this adapter cannot do](README.md#what-this-adapter-cannot-do) lists
what is left out on purpose, and why.

## When a pull request needs an issue first

Open an issue, and agree on the change there, before a pull request that:

- adds a feature, a source config key or a query option;
- changes how a statement, its variables, filters, sorts or pagination
  are rewritten into the query body, or what a result looks like;
- changes the public API: the `Lotus.Elasticsearch` macro, the config
  shape, or what an adapter callback returns;
- adds a dependency;
- touches many files, or needs a design decision.

A pull request does not need an issue when it is small and its reason is
plain from the diff: a typo, a broken link, a wrong sentence in a guide,
or a bug fix with a test that fails without it. When in doubt, open the
issue: a short discussion costs less than a pull request that is not
merged.

A pull request with an issue says so: `Fixes #123` or `Closes #123`.

## A pull request

- **One change.** A fix, the guide for an unrelated case and a README
  edit are three pull requests. Each is reviewed, reverted and released
  on its own.
- **Why, not only what.** The description says the problem the change
  solves, for whom, and what happened before it: an error, a wrong
  result, a query the cluster rejected. Say why a number was chosen when
  the change adds one.
- **Tests.** A bug fix has a test that fails on `main` and passes with
  the fix. A feature has tests of what it does, and of its errors. A
  change to what the adapter sends to the cluster has an integration test
  under `test/integration/`.
- **Docs.** A change a user can see updates the README or
  [Writing Queries](guides/writing-queries.md), and adds an entry to
  [CHANGELOG.md](CHANGELOG.md) under an `## [Unreleased]` heading at the
  top (add the heading if it is not there yet).
- **The checks pass.** CI runs them on Elixir 1.18, 1.19 and 1.20 against
  OpenSearch 2.18; run them first, with the cluster from `mix test.setup`
  up:

  ```sh
  mix format --check-formatted
  mix compile --warnings-as-errors
  mix credo --strict
  mix test
  ```

The pull request template has these as a checklist.

## What the maintainers keep

- **Releases.** The version in `mix.exs`, the release headings of the
  changelog and the tags are changed by the maintainers, at a release.

## Style

Match the code around your change: its naming, its comments and the way
its docs are written. `mix format` and `mix credo --strict` settle the
rest.

## License

By contributing, you agree that your contribution is released under the
MIT License of the project (see [LICENSE](LICENSE)).
