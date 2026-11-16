[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  # The generated gRPC service in lib/gen calls rpc/3 without parentheses.
  locals_without_parens: [rpc: 3],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
