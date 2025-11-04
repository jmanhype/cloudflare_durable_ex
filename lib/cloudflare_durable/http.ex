defmodule CloudflareDurable.HTTP do
  @moduledoc """
  HTTP client for Cloudflare Durable Objects.

  This module provides low-level HTTP request functions for interacting with
  Cloudflare Durable Objects, with comprehensive error handling and validation.
  """

  require Logger

  @type http_method :: :get | :post | :put | :delete | :patch | :head | :options
  @type http_status :: non_neg_integer()
  @type http_headers :: [{String.t(), String.t()}]
  @type http_body :: String.t() | iodata()
  @type request_opts :: keyword()
  @type error_reason :: :invalid_url | :invalid_method | :network_error | :timeout | term()

  @doc """
  Makes an HTTP request with validation and error handling.

  ## Parameters
    * `method` - HTTP method (:get, :post, :put, :delete, etc.)
    * `url` - URL to request (must be a valid URL)
    * `body` - Request body (string or iodata)
    * `headers` - Request headers as list of tuples
    * `opts` - Request options (timeout, pool_timeout, etc.)

  ## Returns
    * `{:ok, status, headers, body}` - Successful response
    * `{:error, reason}` - Request failed with reason

  ## Examples

      iex> CloudflareDurable.HTTP.request(:get, "https://example.com", "", [], [])
      {:ok, 200, [{"content-type", "text/html"}], "<html>...</html>"}

      iex> CloudflareDurable.HTTP.request(:post, "https://api.example.com", "{}", [{"content-type", "application/json"}], [])
      {:ok, 201, [{"content-type", "application/json"}], "{\\"status\\":\\"created\\"}"}
  """
  @spec request(http_method(), String.t(), http_body(), http_headers(), request_opts()) ::
    {:ok, http_status(), http_headers(), String.t()} | {:error, error_reason()}
  def request(method, url, body \\ "", headers \\ [], opts \\ []) do
    # Validate inputs
    with :ok <- validate_method(method),
         :ok <- validate_url(url) do

      # Build and execute request
      finch_request = Finch.build(method, url, headers, body)

      case Finch.request(finch_request, CloudflareDurable.Finch, opts) do
        {:ok, response} ->
          {:ok, response.status, response.headers, response.body}

        {:error, %Mint.TransportError{reason: reason}} ->
          Logger.error("HTTP transport error: #{inspect(reason)}")
          {:error, classify_transport_error(reason)}

        {:error, reason} = error ->
          Logger.error("HTTP request failed: #{inspect(reason)}")
          error
      end
    end
  end

  # Private functions

  @spec validate_method(term()) :: :ok | {:error, :invalid_method}
  defp validate_method(method) when method in [:get, :post, :put, :delete, :patch, :head, :options] do
    :ok
  end

  defp validate_method(method) do
    Logger.warning("Invalid HTTP method: #{inspect(method)}")
    {:error, :invalid_method}
  end

  @spec validate_url(term()) :: :ok | {:error, :invalid_url}
  defp validate_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        :ok
      _ ->
        Logger.warning("Invalid URL: #{inspect(url)}")
        {:error, :invalid_url}
    end
  end

  defp validate_url(url) do
    Logger.warning("URL must be a string: #{inspect(url)}")
    {:error, :invalid_url}
  end

  @spec classify_transport_error(term()) :: error_reason()
  defp classify_transport_error(:timeout), do: :timeout
  defp classify_transport_error(:econnrefused), do: :network_error
  defp classify_transport_error(:nxdomain), do: :network_error
  defp classify_transport_error(:closed), do: :network_error
  defp classify_transport_error(_reason), do: :network_error
end 