defmodule CloudflareDurable.HTTP do
  @moduledoc """
  HTTP client for Cloudflare Durable Objects.
  
  This module provides low-level HTTP request functions for interacting with
  Cloudflare Durable Objects.
  """
  
  @doc """
  Makes an HTTP request.
  
  ## Parameters
    * `method` - HTTP method (:get, :post, :put, :delete, etc.)
    * `url` - URL to request
    * `body` - Request body
    * `headers` - Request headers
    * `opts` - Request options
  
  ## Returns
    * `{:ok, status, headers, body}` - Successful response
    * `{:error, reason}` - Request failed
  """
  @spec request(atom(), String.t(), String.t(), list(), keyword()) :: 
    {:ok, integer(), list(), String.t()} | {:error, term()}
  def request(method, url, body, headers, opts \\ []) do
    finch_request = Finch.build(method, url, headers, body)
    
    case Finch.request(finch_request, CloudflareDurable.Finch, opts) do
      {:ok, response} ->
        {:ok, response.status, response.headers, response.body}
      {:error, _} = error ->
        error
    end
  end
end 