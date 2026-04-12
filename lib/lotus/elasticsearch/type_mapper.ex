defmodule Lotus.Elasticsearch.TypeMapper do
  @moduledoc false

  def to_lotus_type("text"), do: :text
  def to_lotus_type("keyword"), do: :text
  def to_lotus_type("constant_keyword"), do: :text
  def to_lotus_type("wildcard"), do: :text
  def to_lotus_type("long"), do: :integer
  def to_lotus_type("integer"), do: :integer
  def to_lotus_type("short"), do: :integer
  def to_lotus_type("byte"), do: :integer
  def to_lotus_type("unsigned_long"), do: :integer
  def to_lotus_type("double"), do: :float
  def to_lotus_type("float"), do: :float
  def to_lotus_type("half_float"), do: :float
  def to_lotus_type("scaled_float"), do: :decimal
  def to_lotus_type("boolean"), do: :boolean
  def to_lotus_type("date"), do: :datetime
  def to_lotus_type("date_nanos"), do: :datetime
  def to_lotus_type("ip"), do: :text
  def to_lotus_type("object"), do: :json
  def to_lotus_type("nested"), do: :json
  def to_lotus_type("flattened"), do: :json
  def to_lotus_type("geo_point"), do: :text
  def to_lotus_type("geo_shape"), do: :text
  def to_lotus_type("binary"), do: :binary
  def to_lotus_type(_), do: :text
end
