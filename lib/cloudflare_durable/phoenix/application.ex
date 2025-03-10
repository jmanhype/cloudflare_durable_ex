defmodule CloudflareDurable.Phoenix.Application do
  @moduledoc """
  Phoenix adapter application for CloudflareDurable.
  
  This module provides the application configuration for integrating
  CloudflareDurable with Phoenix applications.
  """
  
  use Application
  
  @doc """
  Starts the CloudflareDurable Phoenix adapter.
  """
  @spec start(any, any) :: {:ok, pid()}
  def start(_type, _args) do
    children = [
      # Registry for DurableServer processes
      {Registry, keys: :unique, name: CloudflareDurable.Phoenix.Registry},
      
      # DynamicSupervisor for DurableServer processes
      {DynamicSupervisor, 
        name: CloudflareDurable.Phoenix.ServerSupervisor, 
        strategy: :one_for_one
      },
      
      # PubSub for event distribution
      {Phoenix.PubSub, name: CloudflareDurable.Phoenix.PubSub},
      
      # Presence for tracking clients
      CloudflareDurable.Phoenix.Presence
    ]
    
    opts = [strategy: :one_for_one, name: CloudflareDurable.Phoenix.Supervisor]
    Supervisor.start_link(children, opts)
  end
end 