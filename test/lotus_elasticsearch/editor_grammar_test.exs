defmodule Lotus.Source.Adapters.Elasticsearch.EditorGrammarTest do
  use ExUnit.Case, async: true

  alias Lotus.Source.Adapters.Elasticsearch.EditorConfig
  alias Lotus.Source.Adapters.Elasticsearch.EditorGrammar

  @primitives ~w(string number integer boolean any field index)
  @spec_keys [:object, :fields, :names, :indices, :one_key, :open, :array, :one_of, :enum, :field]

  setup do
    {:ok, grammar: EditorGrammar.grammar()}
  end

  test "rides in the editor config's context schema", %{grammar: grammar} do
    assert EditorConfig.config().context_schema.grammar == grammar
  end

  test "every type it names is defined, and every type is well formed", %{grammar: grammar} do
    assert Map.has_key?(grammar.types, grammar.start)

    for {name, spec} <- grammar.types do
      check(spec, grammar.types, [name])
    end
  end

  test "encodes as JSON, the way the editor receives it", %{grammar: grammar} do
    decoded = grammar |> Jason.encode!() |> Jason.decode!()
    assert decoded["start"] == "search"
    assert decoded["types"]["bool"]["object"]["filter"]["type"] == "queries"
  end

  describe "the request it describes" do
    test "a bool's clauses take a query or a list of them", %{grammar: g} do
      assert member_type(g, "bool", "must") == "queries"
      assert g.types["queries"] == %{one_of: ["query", %{array: "query"}]}
    end

    test "a term is keyed by a field", %{grammar: g} do
      term = g.types["query"].object["term"].type
      assert term.fields == "term_value"
      assert term.object == %{}
    end

    test "an aggregation's buckets are named, and each is typed", %{grammar: g} do
      assert g.types["aggs"] == %{object: %{}, names: "agg"}
      agg = g.types["agg"].object
      assert agg["date_histogram"].type.object["field"] == %{field: ["date", "date_nanos"]}
      assert agg["aggs"].type == "aggs"
    end

    test "only body parameters are top-level keys", %{grammar: g} do
      keys = Map.keys(g.types["search"].object)
      assert "query" in keys and "aggs" in keys and "sort" in keys
      refute "routing" in keys or "preference" in keys or "search_type" in keys
    end
  end

  defp member_type(grammar, type, key), do: grammar.types[type].object[key].type

  defp check(name, types, at) when is_binary(name) do
    assert name in @primitives or Map.has_key?(types, name),
           "#{inspect(name)} at #{Enum.join(at, " > ")} is not a type"
  end

  defp check(%{type: type} = member, types, at) do
    assert Map.keys(member) -- [:type, :doc, :snippet] == [], "bad member at #{inspect(at)}"
    check(type, types, at)
  end

  defp check(%{} = spec, types, at) do
    assert Map.keys(spec) -- @spec_keys == [],
           "unknown keys #{inspect(Map.keys(spec))} at #{inspect(at)}"

    for {key, member} <- Map.get(spec, :object, %{}), do: check(member, types, at ++ [key])

    for key <- [:fields, :names, :indices, :array],
        Map.has_key?(spec, key),
        do: check(spec[key], types, at ++ ["#{key}"])

    for item <- Map.get(spec, :one_of, []), do: check(item, types, at ++ ["one_of"])
    if spec[:enum], do: assert(is_list(spec.enum) and spec.enum != [])
    if spec[:field], do: assert(is_list(spec.field))
  end
end
