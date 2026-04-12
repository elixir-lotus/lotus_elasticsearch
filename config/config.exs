import Config

config :logger, level: :warning

if File.exists?("config/#{config_env()}.exs") do
  import_config "#{config_env()}.exs"
end
