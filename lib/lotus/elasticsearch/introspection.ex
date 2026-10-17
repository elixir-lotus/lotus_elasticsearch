defmodule Lotus.Elasticsearch.Introspection do
  @moduledoc false

  alias Lotus.Elasticsearch.Client

  def list_indices(base_url, opts \\ []) do
    case Client.list_indices(base_url, opts) do
      {:ok, indices} ->
        indices
        |> Enum.map(& &1["index"])
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.sort()

      {:error, _} ->
        []
    end
  end

  @doc """
  Each index's document count, as `{nil, index} => count`, for the indices
  `list_indices/2` lists.
  """
  def index_doc_counts(base_url, opts \\ []) do
    with {:ok, indices} <- Client.list_indices(base_url, opts), do: {:ok, doc_counts(indices)}
  end

  @doc """
  The document counts of `_cat/indices` rows. `docs.count` is a string in
  the JSON form, and is missing for a closed index, which is left out, as
  hidden (`.`-prefixed) indices are. It counts Lucene documents, nested
  ones included, so it estimates an index's top-level document count from
  above.
  """
  def doc_counts(indices) do
    for %{"index" => index} = row <- indices,
        not String.starts_with?(index, "."),
        count = parse_count(row["docs.count"]),
        count != nil,
        into: %{},
        do: {{nil, index}, count}
  end

  defp parse_count(count) when is_integer(count), do: count

  defp parse_count(count) when is_binary(count) do
    case Integer.parse(count) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_count(_count), do: nil

  def get_index_mapping(base_url, index, opts \\ []) do
    case Client.get_mapping(base_url, index, opts) do
      {:ok, mapping} ->
        properties = get_in(mapping, [index, "mappings", "properties"]) || %{}

        Enum.map(properties, fn {field_name, field_def} ->
          %{
            name: field_name,
            type: field_def["type"] || "object",
            nullable: true,
            default: nil,
            primary_key: field_name == "_id"
          }
        end)
        |> Enum.sort_by(& &1.name)

      {:error, _} ->
        []
    end
  end
end
