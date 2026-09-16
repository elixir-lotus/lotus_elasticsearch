defmodule Lotus.Elasticsearch.LifecycleTest do
  # The Finch instance is a named singleton, so these tests cannot share the
  # VM with each other.
  use ExUnit.Case, async: false

  alias Lotus.Elasticsearch.Client
  alias Lotus.Source.Adapters.Elasticsearch, as: Adapter

  @test_url Application.compile_env(:lotus_elasticsearch, :test_url)

  defmodule PooledClient do
    use Lotus.Elasticsearch, otp_app: :lotus_elasticsearch
  end

  defp start_finch do
    [finch] = Adapter.shared_children()
    start_supervised!(finch)
  end

  describe "wrap/2 pool settings" do
    test "uses defaults when the entry sets none" do
      adapter = Adapter.wrap("search", %{adapter: :elasticsearch, url: @test_url})

      assert adapter.state.pool == %{size: 10, count: 1, connect_timeout: 5_000}
      assert adapter.state.http_opts == [receive_timeout: 15_000]
    end

    test "reads the pool settings from a config map" do
      adapter =
        Adapter.wrap("search", %{
          adapter: :elasticsearch,
          url: @test_url,
          username: "elastic",
          password: "secret",
          pool_size: 3,
          pool_count: 2,
          connect_timeout: 1_000,
          receive_timeout: 2_000
        })

      assert adapter.state.pool == %{size: 3, count: 2, connect_timeout: 1_000}

      assert adapter.state.http_opts == [
               username: "elastic",
               password: "secret",
               receive_timeout: 2_000
             ]
    end

    test "reads the pool settings from a client module" do
      Application.put_env(:lotus_elasticsearch, PooledClient,
        url: @test_url,
        pool_size: 4,
        receive_timeout: 500
      )

      on_exit(fn -> Application.delete_env(:lotus_elasticsearch, PooledClient) end)

      adapter = Adapter.wrap("search", PooledClient)

      assert adapter.state.pool.size == 4
      assert adapter.state.http_opts == [receive_timeout: 500]
    end
  end

  describe "shared_children/0" do
    test "returns one Finch named after the adapter" do
      assert [{Finch, opts}] = Adapter.shared_children()
      assert opts[:name] == Client.finch()
      assert %{default: _} = opts[:pools]
    end
  end

  describe "source_started/2" do
    test "adds a pool for the source URL and is safe to run again" do
      start_finch()
      adapter = Adapter.wrap("search", %{adapter: :elasticsearch, url: @test_url, pool_size: 2})

      assert :ok = Adapter.source_started("search", adapter.state)
      assert {:ok, pid} = Finch.find_pool(Client.finch(), Finch.Pool.new(@test_url))
      assert is_pid(pid)

      assert :ok = Adapter.source_started("search", adapter.state)
      assert {:ok, ^pid} = Finch.find_pool(Client.finch(), Finch.Pool.new(@test_url))
    end
  end

  describe "Client.request_options/4" do
    test "goes through Req's default Finch when the adapter's Finch is not running" do
      opts = Client.request_options(:get, @test_url, "/", receive_timeout: 100)

      refute Keyword.has_key?(opts, :finch)
      assert opts[:receive_timeout] == 100
      assert opts[:url] == @test_url <> "/"
    end

    test "goes through the adapter's Finch when it is running" do
      start_finch()

      opts = Client.request_options(:get, @test_url, "/", username: "u", password: "p")

      assert opts[:finch] in [Client.finch(), [name: Client.finch()]]
      assert opts[:auth] == {:basic, "u:p"}
    end
  end

  describe "against the cluster" do
    test "a started source answers a health check through its own pool" do
      start_finch()
      adapter = Adapter.wrap("search", %{adapter: :elasticsearch, url: @test_url})
      :ok = Adapter.source_started("search", adapter.state)

      assert :ok = Adapter.health_check(adapter.state)
    end

    test "a source without a pool yet answers a health check through the default pool" do
      start_finch()
      adapter = Adapter.wrap("search", %{adapter: :elasticsearch, url: @test_url})

      assert :ok = Adapter.health_check(adapter.state)
    end
  end
end
