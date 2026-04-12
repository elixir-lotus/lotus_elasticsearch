defmodule Lotus.Elasticsearch.Test.LotusRepo.Migrations.CreateLotusTables do
  use Ecto.Migration

  defdelegate up, to: Lotus.Migrations.SQLite
  defdelegate down, to: Lotus.Migrations.SQLite
end
