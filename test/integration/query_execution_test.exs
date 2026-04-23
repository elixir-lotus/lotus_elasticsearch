defmodule Lotus.Elasticsearch.Integration.QueryExecutionTest do
  use Lotus.Elasticsearch.Case, async: false

  alias Lotus.Elasticsearch.Test.Fixtures
  alias Lotus.Source.Adapters.Elasticsearch, as: Adapter

  setup do
    Fixtures.create_users_index()
    Fixtures.insert_user(%{name: "Alice", email: "alice@test.com", age: 30, active: true})
    Fixtures.insert_user(%{name: "Bob", email: "bob@test.com", age: 25, active: false})

    adapter =
      Adapter.wrap("search", %{
        adapter: :elasticsearch,
        url: Application.get_env(:lotus_elasticsearch, :test_url)
      })

    %{adapter: adapter, index: Fixtures.users_index()}
  end

  test "executes match_all query", %{adapter: adapter, index: index} do
    query = Lotus.JSON.encode!(%{query: %{match_all: %{}}})

    assert {:ok, result} = Adapter.execute_query(adapter.state, query, [], index: index)
    assert result.num_rows == 2
    assert "name" in result.columns
    assert "email" in result.columns
  end

  test "executes term query", %{adapter: adapter, index: index} do
    query = Lotus.JSON.encode!(%{query: %{term: %{active: true}}})

    assert {:ok, result} = Adapter.execute_query(adapter.state, query, [], index: index)
    assert result.num_rows == 1
  end

  test "returns error for invalid JSON", %{adapter: adapter, index: index} do
    assert {:error, msg} = Adapter.execute_query(adapter.state, "not json", [], index: index)
    assert msg =~ "Invalid JSON"
  end
end
