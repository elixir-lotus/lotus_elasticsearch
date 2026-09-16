defmodule Lotus.Elasticsearch.Client do
  @moduledoc false

  @finch Lotus.Elasticsearch.Finch

  _ = Application.load(:req)

  @finch_option if Version.match?(to_string(Application.spec(:req, :vsn)), ">= 0.7.4"),
                  do: [name: @finch],
                  else: @finch

  @doc """
  The Finch instance the adapter starts through `shared_children/0`.

  Requests go through it when it is running and through Req's default
  Finch otherwise, so the adapter works the same under a Lotus that does
  not supervise source lifecycles.
  """
  def finch, do: @finch

  def request(method, base_url, path, opts \\ []) do
    case Req.request(request_options(method, base_url, path, opts)) do
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

  def request_options(method, base_url, path, opts) do
    url = String.trim_trailing(base_url, "/") <> path

    [method: method, url: url]
    |> maybe_add_json(opts[:json])
    |> maybe_add_auth(opts[:username], opts[:password])
    |> maybe_add_receive_timeout(opts[:receive_timeout])
    |> maybe_add_finch(Process.whereis(@finch))
  end

  defp maybe_add_json(opts, nil), do: opts
  defp maybe_add_json(opts, json), do: Keyword.put(opts, :json, json)

  defp maybe_add_auth(opts, nil, _), do: opts

  defp maybe_add_auth(opts, username, password) do
    Keyword.put(opts, :auth, {:basic, "#{username}:#{password}"})
  end

  defp maybe_add_receive_timeout(opts, nil), do: opts
  defp maybe_add_receive_timeout(opts, timeout), do: Keyword.put(opts, :receive_timeout, timeout)

  defp maybe_add_finch(opts, nil), do: opts
  defp maybe_add_finch(opts, _pid), do: Keyword.put(opts, :finch, @finch_option)
end
