Application.ensure_all_started(:ecto_sqlite3)

{:ok, _} = Lotus.Elasticsearch.Test.LotusRepo.start_link()

sqlite_migrations = Path.join([File.cwd!(), "test/support/sqlite/migrations"])

_ =
  Ecto.Migrator.run(
    Lotus.Elasticsearch.Test.LotusRepo,
    sqlite_migrations,
    :up,
    all: true,
    log: false
  )

ExUnit.start()
