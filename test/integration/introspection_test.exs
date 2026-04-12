defmodule Lotus.Elasticsearch.Integration.IntrospectionTest do
  use Lotus.Elasticsearch.Case, async: false

  alias Lotus.Elasticsearch.Test.Fixtures
  alias Lotus.Source.Adapters.Elasticsearch, as: Adapter

  setup do
    Fixtures.create_users_index()

    adapter =
      Adapter.wrap("search", %{
        adapter: :elasticsearch,
        url: Application.get_env(:lotus_elasticsearch, :test_url)
      })

    %{adapter: adapter}
  end

  test "list_tables returns indices", %{adapter: adapter} do
    {:ok, tables} = Adapter.list_tables(adapter.state, [], [])
    index_names = Enum.map(tables, &elem(&1, 1))
    assert Fixtures.users_index() in index_names
  end

  test "get_table_schema returns field mappings", %{adapter: adapter} do
    {:ok, columns} = Adapter.get_table_schema(adapter.state, nil, Fixtures.users_index())
    column_names = Enum.map(columns, & &1.name)
    assert "name" in column_names
    assert "email" in column_names
    assert "age" in column_names
  end

  test "list_schemas returns empty", %{adapter: adapter} do
    assert {:ok, []} = Adapter.list_schemas(adapter.state)
  end
end
