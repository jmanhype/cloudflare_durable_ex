import Config

config :cloudflare_durable,
  # These are placeholder values that should be overridden in the application using the package
  worker_url: System.get_env("CLOUDFLARE_WORKER_URL") || "https://example.cloudflare.workers.dev",
  account_id: System.get_env("CLOUDFLARE_ACCOUNT_ID"),
  api_token: System.get_env("CLOUDFLARE_API_TOKEN") 