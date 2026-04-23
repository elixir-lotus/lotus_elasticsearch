import Config

config :lotus_elasticsearch, :test_url, "http://localhost:9209"
config :lotus_elasticsearch, :test_index_prefix, "lotus_test"

config :lotus_elasticsearch, Lotus.Elasticsearch.Test.LotusRepo,
  database: ":memory:",
  pool_size: 1

config :lotus, storage_repo: Lotus.Elasticsearch.Test.LotusRepo
