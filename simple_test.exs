#!/usr/bin/env elixir

Mix.start()
Application.ensure_all_started(:jason)
Application.ensure_all_started(:finch)

# Start Finch with a name (ignore if already started)
case Finch.start_link(name: CloudflareDurable.Finch) do
  {:ok, _} -> IO.puts("Started Finch")
  {:error, {:already_started, _}} -> IO.puts("Finch already started")
  other -> IO.puts("Error starting Finch: #{inspect(other)}")
end

worker_url = "https://cloudflare-durable-worker.straughter-guthrie.workers.dev"
object_id = "test-counter-#{:os.system_time(:millisecond)}"

IO.puts("Testing with worker_url: #{worker_url}")
IO.puts("Testing with object_id: #{object_id}")

# Initialize request
IO.puts("\n== Testing initialization ==")
init_url = "#{worker_url}/initialize/#{object_id}"
init_body = Jason.encode!(%{value: 0})

IO.puts("POST #{init_url}")
IO.puts("Body: #{init_body}")

init_req = Finch.build(:post, init_url, [{"content-type", "application/json"}], init_body)
{:ok, init_resp} = Finch.request(init_req, CloudflareDurable.Finch)

IO.puts("Response status: #{init_resp.status}")
IO.puts("Response body: #{init_resp.body}")

if init_resp.status in 200..299 do
  # Call method request
  IO.puts("\n== Testing method call ==")
  method_url = "#{worker_url}/object/#{object_id}/method/method_increment"
  method_body = Jason.encode!(%{increment: 1})
  
  IO.puts("POST #{method_url}")
  IO.puts("Body: #{method_body}")
  
  method_req = Finch.build(:post, method_url, [{"content-type", "application/json"}], method_body)
  {:ok, method_resp} = Finch.request(method_req, CloudflareDurable.Finch)
  
  IO.puts("Response status: #{method_resp.status}")
  IO.puts("Response body: #{method_resp.body}")
  
  # Get state request
  IO.puts("\n== Testing get state ==")
  state_url = "#{worker_url}/object/#{object_id}/state"
  
  IO.puts("GET #{state_url}")
  
  state_req = Finch.build(:get, state_url)
  {:ok, state_resp} = Finch.request(state_req, CloudflareDurable.Finch)
  
  IO.puts("Response status: #{state_resp.status}")
  IO.puts("Response body: #{state_resp.body}")
end

IO.puts("\n✨ Test complete!") 