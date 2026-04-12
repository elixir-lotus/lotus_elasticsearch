defmodule Lotus.Elasticsearch.TypeMapperTest do
  use ExUnit.Case, async: true

  alias Lotus.Elasticsearch.TypeMapper

  test "maps ES types to Lotus types" do
    assert TypeMapper.to_lotus_type("text") == :text
    assert TypeMapper.to_lotus_type("keyword") == :text
    assert TypeMapper.to_lotus_type("long") == :integer
    assert TypeMapper.to_lotus_type("integer") == :integer
    assert TypeMapper.to_lotus_type("short") == :integer
    assert TypeMapper.to_lotus_type("byte") == :integer
    assert TypeMapper.to_lotus_type("double") == :float
    assert TypeMapper.to_lotus_type("float") == :float
    assert TypeMapper.to_lotus_type("half_float") == :float
    assert TypeMapper.to_lotus_type("scaled_float") == :decimal
    assert TypeMapper.to_lotus_type("boolean") == :boolean
    assert TypeMapper.to_lotus_type("date") == :datetime
    assert TypeMapper.to_lotus_type("ip") == :text
    assert TypeMapper.to_lotus_type("object") == :json
    assert TypeMapper.to_lotus_type("nested") == :json
    assert TypeMapper.to_lotus_type("flattened") == :json
    assert TypeMapper.to_lotus_type("geo_point") == :text
    assert TypeMapper.to_lotus_type("unknown_type") == :text
  end
end
