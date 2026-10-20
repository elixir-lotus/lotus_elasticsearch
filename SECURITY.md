# Security

## Reporting a vulnerability

Do not open a public issue for a security problem. Report it privately
through GitHub: [Report a vulnerability](https://github.com/elixir-lotus/lotus_elasticsearch/security/advisories/new).

Say what an attacker can do, and how: the statement, its variables and
options, the source config, and the steps or the payload. Name the
cluster (Elasticsearch or OpenSearch) and its version. We answer within a
week, agree on a fix and a date, and credit you in the advisory unless you
ask us not to.

## Supported versions

Security fixes are made to the latest release. Lotus Elasticsearch is
before 1.0, so a fix is not backported to an earlier minor version.

## What is in scope

The adapter turns a Lotus statement, with variables a person may type,
into HTTP requests to your cluster. A problem is in scope when, through
the adapter, a person can:

- **break out of query translation:** make a `{{var}}` value, a filter, a
  sort or a pagination value change the structure of the query body
  rather than land in it as a JSON literal;
- **get past read-only use:** make the adapter send a request other than
  a search, a mapping or index listing, or a validation, such as one that
  writes, deletes or changes cluster settings, or reach a path other than
  the one the adapter means to call;
- **expose credentials:** see the source's username and password, or any
  header that carries them, in a result, an error, a log line, the AI
  context or the editor config;
- **see indices it should not:** have schema introspection
  (`list_tables`, `describe_table`, index sizes) list or describe dot-prefixed
  system indices, or indices the adapter is meant to hide;
- **make the adapter or the cluster do unbounded work**, or crash the
  process that runs the query.

Who may read which index is decided by the cluster's own security
(Elasticsearch security or the OpenSearch security plugin) and by the
user the source connects as: with `allow_unrestricted_resources`, Lotus
does not check which indices a statement reads (see
[Visibility](README.md#visibility)). Giving the source a user with only
the read permissions it needs is the app's job.
