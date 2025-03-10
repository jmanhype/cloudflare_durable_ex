[
  # Common false positives
  {"lib/cloudflare_durable/websocket/connection.ex", :pattern_match},
  
  # Third-party dependencies
  ~r/.*\.beam/,

  # Known external behaviors that Dialyzer can't analyze correctly
  {"lib/cloudflare_durable.ex", :unknown_function, {:application, :get_env, 3}},
  {"lib/cloudflare_durable/client.ex", :unknown_function, {:mint_web_socket, :new, 2}},

  # Ignore specs for unused callback implementations
  {:unmatched_returns, :_}
] 