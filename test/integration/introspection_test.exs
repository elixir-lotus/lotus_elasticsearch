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

  test "describe_table returns field mappings", %{adapter: adapter} do
    {:ok, columns} = Adapter.describe_table(adapter.state, nil, Fixtures.users_index())
    column_names = Enum.map(columns, & &1.name)
    assert "name" in column_names
    assert "email" in column_names
    assert "age" in column_names
  end

  test "table_row_estimates returns each index's document count", %{adapter: adapter} do
    {:ok, estimates} = Adapter.table_row_estimates(adapter.state, [])
    assert is_integer(estimates[{nil, Fixtures.users_index()}])
    refute Enum.any?(estimates, fn {{nil, index}, _} -> String.starts_with?(index, ".") end)
  end

  test "describe_table lists sub-fields, object and nested fields as dotted paths", %{
    adapter: adapter
  } do
    index = "#{@prefix}_nested"

    Lotus.Elasticsearch.Client.request(:put, @base_url, "/#{index}",
      json: %{
        mappings: %{
          properties: %{
            customer: %{type: "text", fields: %{keyword: %{type: "keyword"}}},
            address: %{properties: %{city: %{type: "keyword"}}},
            lines: %{type: "nested", properties: %{sku: %{type: "keyword"}}}
          }
        }
      }
    )

    {:ok, columns} = Adapter.describe_table(adapter.state, nil, index)

    assert Enum.map(columns, &{&1.name, &1.type}) == [
             {"address", "object"},
             {"address.city", "keyword"},
             {"customer", "text"},
             {"customer.keyword", "keyword"},
             {"lines", "nested"},
             {"lines.sku", "keyword"}
           ]
  end

  test "list_schemas returns empty", %{adapter: adapter} do
    assert {:ok, []} = Adapter.list_schemas(adapter.state)
  end
end
