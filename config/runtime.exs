import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/mobile_car_wash start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :mobile_car_wash, MobileCarWashWeb.Endpoint, server: true
end

config :mobile_car_wash, MobileCarWashWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Google Analytics (all environments — tag only emitted when set)
if ga_id = System.get_env("GOOGLE_ANALYTICS_ID") do
  config :mobile_car_wash, :google_analytics_id, ga_id
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :mobile_car_wash, MobileCarWash.Repo,
    ssl: [verify: :verify_none],
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :mobile_car_wash, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :mobile_car_wash, MobileCarWashWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :mobile_car_wash, MobileCarWashWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :mobile_car_wash, MobileCarWashWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # Stripe
  config :stripity_stripe,
    api_key: System.get_env("STRIPE_SECRET_KEY") || raise("STRIPE_SECRET_KEY is required")

  config :mobile_car_wash,
    stripe_webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET") || raise("STRIPE_WEBHOOK_SECRET is required"),
    base_url: "https://#{host}"

  # Token signing secret
  config :mobile_car_wash,
    token_signing_secret:
      System.get_env("TOKEN_SIGNING_SECRET") || raise("TOKEN_SIGNING_SECRET is required")

  # Admin emails (runtime override)
  if admin_email = System.get_env("ADMIN_EMAIL") do
    config :mobile_car_wash, :admin_emails, [admin_email]
  end

  # S3 photo storage (production)
  config :mobile_car_wash, :photo_storage, :s3
  config :mobile_car_wash, :s3_bucket, System.get_env("S3_BUCKET") || raise("S3_BUCKET is required")
  config :mobile_car_wash, :s3_region, System.get_env("AWS_REGION") || "us-east-1"

  config :ex_aws,
    access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
    region: System.get_env("AWS_REGION") || "us-east-1"

  # DigitalOcean Spaces uses a custom S3-compatible endpoint
  if s3_endpoint = System.get_env("AWS_S3_ENDPOINT") do
    config :ex_aws, :s3, %{
      scheme: "https://",
      host: URI.parse(s3_endpoint).host,
      region: System.get_env("AWS_REGION") || "us-east-1"
    }
  end

  # Twilio SMS (optional — SMS disabled if not set)
  if System.get_env("TWILIO_ACCOUNT_SID") do
    config :mobile_car_wash, :twilio,
      account_sid: System.get_env("TWILIO_ACCOUNT_SID"),
      auth_token: System.get_env("TWILIO_AUTH_TOKEN"),
      from_number: System.get_env("TWILIO_FROM_NUMBER")
  end

  # Mailer — Zoho SMTP (swap relay/port/credentials for any SMTP provider)
  config :mobile_car_wash, MobileCarWash.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: System.get_env("SMTP_RELAY") || "smtp.zoho.com",
    port: String.to_integer(System.get_env("SMTP_PORT") || "465"),
    username: System.get_env("SMTP_USERNAME") || raise("SMTP_USERNAME is required"),
    password: System.get_env("SMTP_PASSWORD") || raise("SMTP_PASSWORD is required"),
    ssl: true,
    auth: :always

  # From email address
  config :mobile_car_wash, :from_email,
    System.get_env("FROM_EMAIL") || "hello@drivewaydetailcosa.com"

  # Accounting provider — configurable: "zoho" (default), "quickbooks", or "none"
  accounting_provider =
    case System.get_env("ACCOUNTING_PROVIDER", "zoho") do
      "quickbooks" -> MobileCarWash.Accounting.QuickBooks
      "zoho" -> MobileCarWash.Accounting.ZohoBooks
      "none" -> nil
      _ -> MobileCarWash.Accounting.ZohoBooks
    end

  if accounting_provider do
    config :mobile_car_wash, :accounting_provider, accounting_provider
  end

  # Zoho Books credentials (used when ACCOUNTING_PROVIDER=zoho)
  if System.get_env("ZOHO_ORG_ID") do
    config :mobile_car_wash, :zoho_books,
      organization_id: System.get_env("ZOHO_ORG_ID"),
      client_id: System.get_env("ZOHO_CLIENT_ID"),
      client_secret: System.get_env("ZOHO_CLIENT_SECRET"),
      refresh_token: System.get_env("ZOHO_REFRESH_TOKEN"),
      api_url: System.get_env("ZOHO_API_URL") || "https://www.zohoapis.com/books/v3"
  end

  # QuickBooks Online credentials (used when ACCOUNTING_PROVIDER=quickbooks)
  if System.get_env("QUICKBOOKS_COMPANY_ID") do
    config :mobile_car_wash, :quickbooks,
      company_id: System.get_env("QUICKBOOKS_COMPANY_ID"),
      client_id: System.get_env("QUICKBOOKS_CLIENT_ID"),
      client_secret: System.get_env("QUICKBOOKS_CLIENT_SECRET"),
      refresh_token: System.get_env("QUICKBOOKS_REFRESH_TOKEN"),
      api_url: System.get_env("QUICKBOOKS_API_URL") || "https://quickbooks.api.intuit.com"
  end
end
