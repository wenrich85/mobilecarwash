import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :mobile_car_wash, MobileCarWash.Repo,
  username: "wrich",
  password: "",
  hostname: "localhost",
  database: "mobile_car_wash_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :mobile_car_wash, MobileCarWashWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "EhTxrgJEk18n6qEZNU0/EMBRbQvWqyXaBup2lFUKsfa91spn/RVVsHjz3XjEZ8g2",
  server: false

# In test we don't send emails
config :mobile_car_wash, MobileCarWash.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Oban: inline mode for testing (jobs execute immediately)
config :mobile_car_wash, Oban, testing: :inline

# Token signing secret for authentication (test)
config :mobile_car_wash, :token_signing_secret, "test-only-secret-change-in-production-at-least-64-chars-long-please"

# Use mock Twilio client in tests
config :mobile_car_wash, :twilio_client, MobileCarWash.Notifications.TwilioClientMock

# Use mock APNs client in tests
config :mobile_car_wash, :apns_client, MobileCarWash.Notifications.ApnsClientMock

# Use the ETS-backed mock vision client in tests so no photo bytes ever
# leave the VM.
config :mobile_car_wash, :vision_client, MobileCarWash.AI.VisionClientMock

# Use the ETS-backed mock image generator in tests so no tokens are
# ever spent on OpenAI DALL-E calls from CI.
config :mobile_car_wash, :image_generator, MobileCarWash.AI.ImageGeneratorMock

# Use mock Stripe Product/Price modules in tests so ServiceType/SubscriptionPlan
# CRUD doesn't hit the live Stripe API.
config :mobile_car_wash, :stripe_product_module, MobileCarWash.Billing.StripeProductMock
config :mobile_car_wash, :stripe_price_module, MobileCarWash.Billing.StripePriceMock
config :mobile_car_wash, :stripe_payment_intent_module, MobileCarWash.Billing.StripePaymentIntentMock

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
