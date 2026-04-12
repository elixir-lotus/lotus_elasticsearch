defmodule Lotus.ElasticsearchMacroTest do
  use ExUnit.Case, async: true

  defmodule TestClient do
    use Lotus.Elasticsearch, otp_app: :lotus_elasticsearch
  end

  test "__elasticsearch__/0 returns true" do
    assert TestClient.__elasticsearch__() == true
  end

  test "config/0 reads from application env" do
    Application.put_env(:lotus_elasticsearch, TestClient, url: "http://test:9200")
    assert TestClient.config()[:url] == "http://test:9200"
  after
    Application.delete_env(:lotus_elasticsearch, TestClient)
  end
end
