defmodule Lotus.Elasticsearch.Integration.LotusPipelineTest do
  # Runs statements through Lotus itself, as Lotus Web does, against the
  # cluster: variables, optional blocks, read-only and cancel.
  use Lotus.Elasticsearch.Case, async: false

  alias Lotus.Elasticsearch.Client
  alias Lotus.Elasticsearch.Test.Fixtures
  alias Lotus.Storage.Query
  alias Lotus.Storage.QueryVariable

  @lotus_env [
    source_adapters: [Lotus.Source.Adapters.Elasticsearch],
    data_sources: %{"search" => %{adapter: :elasticsearch, url: "http://localhost:9209"}},
    default_source: "search",
    allow_unrestricted_resources: true
  ]

  setup do
    previous = for {key, _} <- @lotus_env, do: {key, Application.fetch_env(:lotus, key)}

    for {key, value} <- @lotus_env, do: Application.put_env(:lotus, key, value)
    Lotus.Config.reload!()

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, v} -> Application.put_env(:lotus, key, v)
          :error -> Application.delete_env(:lotus, key)
        end
      end

      Lotus.Config.reload!()
    end)

    Fixtures.create_users_index()
    Fixtures.insert_user(%{name: "Alice", email: "alice@test.com", age: 30, active: true})
    Fixtures.insert_user(%{name: "Bob", email: "bob@test.com", age: 25, active: false})
    :ok
  end

  defp run(statement, vars) do
    query = %Query{
      statement: statement,
      data_source: "search",
      variables: for(name <- Map.keys(vars), do: %QueryVariable{name: name, type: :text})
    }

    case Lotus.run_query(query, vars: vars, index: Fixtures.users_index()) do
      {:ok, result} -> {:ok, Enum.sort(for row <- result.rows, do: row_email(result, row))}
      error -> error
    end
  end

  defp row_email(%{columns: columns}, row),
    do: Enum.at(row, Enum.find_index(columns, &(&1 == "email")))

  test "binds a variable that is a whole string" do
    assert {:ok, ["alice@test.com"]} =
             run(~s({"query": {"term": {"email": "{{email}}"}}}), %{"email" => "alice@test.com"})
  end

  test "binds a bare variable in value position" do
    assert {:ok, ["alice@test.com"]} =
             run(~s({"query": {"range": {"age": {"gte": {{min}}}}}}), %{"min" => "28"})
  end

  test "binds a variable inside a longer string" do
    assert {:ok, ["bob@test.com"]} =
             run(~s({"query": {"wildcard": {"email": "{{who}}@*"}}}), %{"who" => "bob"})
  end

  test "keeps or drops an optional member of an object" do
    statement =
      ~s({"query": {"bool": {"must": {"match_all": {}} [[, "filter": {"term": {"email": "{{email}}"}}]]}}})

    assert {:ok, ["alice@test.com", "bob@test.com"]} = run(statement, %{})
    assert {:ok, ["bob@test.com"]} = run(statement, %{"email" => "bob@test.com"})
  end

  test "a search never writes, whatever the source's read-only setting" do
    refute Lotus.writes?(~s({"query": {"match_all": {}}}), repo: "search")

    assert {:ok, %{num_rows: 2}} =
             Lotus.run_statement(~s({"query": {"match_all": {}}}), [],
               repo: "search",
               index: Fixtures.users_index(),
               read_only: false
             )
  end

  test "a running search can be cancelled" do
    assert Lotus.cancellable?("search")

    docs = Enum.map_join(1..20_000, fn i -> ~s({"index":{}}\n{"name":"u#{i}","age":#{i}}\n) end)

    {:ok, _} =
      Req.post(
        Client.request_options(
          :post,
          @base_url,
          "/#{Fixtures.users_index()}/_bulk?refresh=true",
          []
        ) ++
          [body: docs, headers: [{"content-type", "application/x-ndjson"}]]
      )

    slow =
      ~S|{"query": {"bool": {"filter": {"script": {"script": {"source": | <>
        ~S|"long x = 0; for (int i = 0; i < 900000; i++) { x += i; } return x > 0;"}}}}}}|

    parent = self()

    task =
      Task.async(fn ->
        Lotus.run_statement(slow, [],
          repo: "search",
          index: Fixtures.users_index(),
          timeout: 60_000,
          on_cancel_token: &send(parent, {:token, &1})
        )
      end)

    # The search scores 20,000 documents with a script that loops 900,000
    # times on each: several seconds. Cancelled after 300 ms, it returns
    # long before.
    assert_receive {:token, token}, 5_000
    started = System.monotonic_time(:millisecond)
    Process.sleep(300)
    assert :ok = Lotus.cancel(token)
    assert {:error, "The query was cancelled."} = Task.await(task, 60_000)
    assert System.monotonic_time(:millisecond) - started < 2_000
  end
end
