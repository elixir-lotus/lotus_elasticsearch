defmodule Lotus.Elasticsearch.Test.LotusRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :lotus_elasticsearch,
    adapter: Ecto.Adapters.SQLite3
end
