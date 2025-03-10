#!/usr/bin/env elixir

# Make sure the package is in the code path
Code.prepend_path("_build/dev/lib/cloudflare_durable/ebin")
Code.prepend_path("_build/dev/lib/jason/ebin")
Code.prepend_path("_build/dev/lib/finch/ebin")
Code.prepend_path("_build/dev/lib/mint_web_socket/ebin")
Code.prepend_path("_build/dev/lib/telemetry/ebin")

# Application.ensure_all_started(:cloudflare_durable)

defmodule CollaborativeDocumentExample do
  @moduledoc """
  Example showing how to use CloudflareDurable to implement collaborative document editing.
  
  This simulates multiple users making changes to the same document in real-time,
  with changes being synchronized through a Durable Object.
  """
  
  def run do
    # Configure the worker URL
    worker_url = System.get_env("CLOUDFLARE_WORKER_URL") || 
                 raise "Please set the CLOUDFLARE_WORKER_URL environment variable"
                 
    Application.put_env(:cloudflare_durable, :worker_url, worker_url)
    
    # Generate a unique document ID
    document_id = "document-#{:os.system_time(:millisecond)}"
    IO.puts("Using document ID: #{document_id}")
    
    # Initialize the document with starting content
    initial_content = "# Collaborative Document\n\nThis is a test document that multiple users can edit."
    
    case CloudflareDurable.initialize(document_id, %{
      content: initial_content,
      version: 1,
      last_modified: DateTime.utc_now() |> DateTime.to_iso8601()
    }) do
      {:ok, response} ->
        IO.puts("Initialized document: #{inspect(response)}")
        
        # Open a WebSocket connection to receive real-time updates
        {:ok, socket} = CloudflareDurable.open_websocket(document_id)
        
        # Spawn a process to handle WebSocket messages
        spawn_link(fn -> handle_messages() end)
        
        # Simulate multiple users making edits
        simulate_user_edits(document_id)
        
      {:error, reason} ->
        IO.puts("Error initializing document: #{inspect(reason)}")
    end
  end
  
  defp simulate_user_edits(document_id) do
    # Simulate User 1 adding a paragraph
    IO.puts("\nUser 1 is adding a paragraph...")
    update_document(document_id, "# Collaborative Document\n\nThis is a test document that multiple users can edit.\n\n## Introduction\n\nThis document demonstrates real-time collaboration using Cloudflare Durable Objects.")
    Process.sleep(2000)
    
    # Simulate User 2 adding a section
    IO.puts("\nUser 2 is adding a new section...")
    update_document(document_id, "# Collaborative Document\n\nThis is a test document that multiple users can edit.\n\n## Introduction\n\nThis document demonstrates real-time collaboration using Cloudflare Durable Objects.\n\n## Features\n\n- Real-time updates\n- Conflict resolution\n- Distributed state")
    Process.sleep(2000)
    
    # Simulate User 3 fixing a typo
    IO.puts("\nUser 3 is fixing a typo...")
    update_document(document_id, "# Collaborative Document\n\nThis is a collaborative document that multiple users can edit.\n\n## Introduction\n\nThis document demonstrates real-time collaboration using Cloudflare Durable Objects.\n\n## Features\n\n- Real-time updates\n- Conflict resolution\n- Distributed state")
    Process.sleep(2000)
    
    # Get final state
    case CloudflareDurable.get_state(document_id) do
      {:ok, state} ->
        IO.puts("\nFinal document state: #{inspect(state)}")
        
      {:error, reason} ->
        IO.puts("Error getting document state: #{inspect(reason)}")
    end
    
    IO.puts("\nSimulation complete. Press Ctrl+C twice to exit.")
  end
  
  defp update_document(document_id, content) do
    case CloudflareDurable.call_method(document_id, "method_update", %{content: content}) do
      {:ok, %{"result" => result}} ->
        IO.puts("Document updated to version #{result["version"]}")
        
      {:error, reason} ->
        IO.puts("Error updating document: #{inspect(reason)}")
    end
  end
  
  defp handle_messages do
    receive do
      {:durable_object_message, message} ->
        case message do
          %{"type" => "update", "key" => "document", "value" => doc} ->
            IO.puts("\nReceived document update:")
            IO.puts("Version: #{doc["version"]}")
            IO.puts("Modified: #{doc["lastModified"]}")
            IO.puts("Content length: #{String.length(doc["content"])} characters")
            
          other ->
            IO.puts("Received other message: #{inspect(other)}")
        end
        
        handle_messages()
        
      other ->
        IO.puts("Received unknown message: #{inspect(other)}")
        handle_messages()
    after
      30000 ->
        IO.puts("No messages received for 30 seconds, exiting message handler")
    end
  end
end

CollaborativeDocumentExample.run() 