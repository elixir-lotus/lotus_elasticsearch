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
