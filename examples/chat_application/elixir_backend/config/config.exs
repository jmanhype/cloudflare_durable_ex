import Config

config :chat_app,
  cloudflare_worker_url: System.get_env("CLOUDFLARE_WORKER_URL") || "http://localhost:8787",
  cloudflare_api_token: System.get_env("CLOUDFLARE_API_TOKEN")

config :chat_app, ChatApp.Endpoint,
  url: [host: "localhost"],
  http: [port: 4000],
  secret_key_base: "ThisIsASecretKeyBaseForDevEnvironmentChangeForProduction",
  render_errors: [formats: [html: ChatApp.ErrorHTML, json: ChatApp.ErrorJSON]],
  pubsub_server: ChatApp.PubSub,
  live_view: [signing_salt: "ThisIsASigningSaltForDevEnvironmentChangeForProduction"]

# Configure the Phoenix endpoint
config :phoenix, :json_library, Jason

# Import environment specific config
import_config "#{config_env()}.exs" 