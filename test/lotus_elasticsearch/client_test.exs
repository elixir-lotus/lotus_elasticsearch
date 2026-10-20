defmodule Lotus.Elasticsearch.ClientTest do
  use ExUnit.Case, async: true

  alias Lotus.Elasticsearch.Client

  # Nothing listens here: a check that lets a value through would fail
  # with a connection error, not the invalid-index error.
  @url "http://127.0.0.1:1"

  describe "check_target/1" do
    test "passes index names, patterns, lists, _all and remote clusters" do
      for index <- ["users", "app.logs.2025-01", "logs-*", "a,b", "_all", "remote:users"] do
        assert Client.check_target(index) == :ok, inspect(index)
      end
    end

    test "refuses a value that leaves the path segment or names another API" do
      for index <- [
            "x/_delete_by_query?q=*&",
            "../_cluster/settings",
            "users?refresh=true",
            "users#frag",
            "users%2F_doc",
            "us\\ers",
            "a b",
            "a\nb",
            ~s(a"b),
            "<logs-{now/d}>",
            "",
            ".",
            ".."
          ] do
        assert {:error, "invalid index: " <> _} = Client.check_target(index), inspect(index)
      end
    end

    test "refuses a value that is not a string" do
      assert {:error, "invalid index: " <> _} = Client.check_target(nil)
      assert {:error, "invalid index: " <> _} = Client.check_target(["a", "b"])
    end
  end

  describe "search/4 and get_mapping/3" do
    test "send no request for an invalid index" do
      assert {:error, "invalid index: " <> _} =
               Client.search(@url, "x/_delete_by_query?q=*&", %{"query" => %{}})

      assert {:error, "invalid index: " <> _} = Client.get_mapping(@url, "x/_settings")
    end
  end
end
