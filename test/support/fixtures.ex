defmodule Lotus.Elasticsearch.Test.Fixtures do
  @moduledoc false

  alias Lotus.Elasticsearch.Client

  @base_url Application.compile_env(:lotus_elasticsearch, :test_url)
  @prefix Application.compile_env(:lotus_elasticsearch, :test_index_prefix)

  def create_users_index do
    Client.request(:put, @base_url, "/#{@prefix}_users",
      json: %{
        mappings: %{
          properties: %{
            name: %{type: "text"},
            email: %{type: "keyword"},
            age: %{type: "integer"},
            active: %{type: "boolean"},
            created_at: %{type: "date"}
          }
        }
      }
    )
  end

  def insert_user(attrs) do
    Client.request(:post, @base_url, "/#{@prefix}_users/_doc?refresh=true", json: attrs)
  end

  def users_index, do: "#{@prefix}_users"
end
