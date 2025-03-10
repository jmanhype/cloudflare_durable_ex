import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :chat_app, ChatApp.Endpoint,
  http: [port: 4002],
  server: false

# Use test Cloudflare Worker URL and API token for tests
config :chat_app,
  cloudflare_worker_url: "http://localhost:8787",
  cloudflare_api_token: "test_token" 