defmodule Lotus.Elasticsearch.IntrospectionTest do
  use ExUnit.Case, async: true

  alias Lotus.Elasticsearch.Introspection

  describe "doc_counts/1" do
    test "reads _cat/indices rows as {nil, index} => count" do
      rows = [
        %{"index" => "users", "health" => "green", "docs.count" => "1204"},
        %{"index" => "events", "health" => "yellow", "docs.count" => 9_800_000}
      ]

      assert Introspection.doc_counts(rows) == %{
               {nil, "users"} => 1204,
               {nil, "events"} => 9_800_000
             }
    end

    test "leaves out hidden indices and those without a count (closed)" do
      rows = [
        %{"index" => ".kibana", "docs.count" => "12"},
        %{"index" => "archived", "docs.count" => nil},
        %{"index" => "broken", "docs.count" => "n/a"},
        %{"index" => "orders", "docs.count" => "3"}
      ]

      assert Introspection.doc_counts(rows) == %{{nil, "orders"} => 3}
    end
  end
end
