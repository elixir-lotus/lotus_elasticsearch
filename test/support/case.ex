defmodule Lotus.Elasticsearch.Case do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Lotus.Elasticsearch.Client

  @base_url Application.compile_env(:lotus_elasticsearch, :test_url)
  @prefix Application.compile_env(:lotus_elasticsearch, :test_index_prefix)

  using do
    quote do
      @base_url unquote(@base_url)
      @prefix unquote(@prefix)
    end
  end

  setup do
    cleanup_test_indices()
    :ok
  end

  defp cleanup_test_indices do
    case Client.list_indices(@base_url) do
      {:ok, indices} ->
        indices
        |> Enum.map(& &1["index"])
        |> Enum.filter(&String.starts_with?(&1, @prefix))
        |> Enum.each(&Client.request(:delete, @base_url, "/#{&1}"))

      _ ->
        :ok
    end
  end
end
