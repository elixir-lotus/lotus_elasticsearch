defmodule Lotus.Elasticsearch.Client do
  @moduledoc false

  def request(method, base_url, path, opts \\ []) do
    url = String.trim_trailing(base_url, "/") <> path

    req_opts =
      [method: method, url: url]
      |> maybe_add_json(opts[:json])
      |> maybe_add_auth(opts[:username], opts[:password])

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, %{status: status, body: body}}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  def search(base_url, index, query, opts \\ []) do
    case request(:post, base_url, "/#{index}/_search", Keyword.merge(opts, json: query)) do
      {:ok, %{body: body}} -> {:ok, body}
      error -> error
    end
  end

  def get_mapping(base_url, index, opts \\ []) do
    case request(:get, base_url, "/#{index}/_mapping", opts) do
      {:ok, %{body: body}} -> {:ok, body}
      error -> error
    end
  end

  def list_indices(base_url, opts \\ []) do
    case request(:get, base_url, "/_cat/indices?format=json&h=index,health,docs.count", opts) do
      {:ok, %{body: body}} when is_list(body) -> {:ok, body}
      error -> error
    end
  end

  defp maybe_add_json(opts, nil), do: opts
  defp maybe_add_json(opts, json), do: Keyword.put(opts, :json, json)

  defp maybe_add_auth(opts, nil, _), do: opts

  defp maybe_add_auth(opts, username, password) do
    Keyword.put(opts, :auth, {:basic, "#{username}:#{password}"})
  end
end
