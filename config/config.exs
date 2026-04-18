# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :mobile_car_wash,
  ecto_repos: [MobileCarWash.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [
    MobileCarWash.Accounts,
    MobileCarWash.Fleet,
    MobileCarWash.Scheduling,
    MobileCarWash.Billing,
    MobileCarWash.Analytics,
    MobileCarWash.Audit,
    MobileCarWash.Operations,
    MobileCarWash.Compliance,
    MobileCarWash.CashFlow,
    MobileCarWash.Loyalty,
    MobileCarWash.Inventory,
    MobileCarWash.Notifications
  ]

# Oban background job configuration
config :mobile_car_wash, Oban,
  repo: MobileCarWash.Repo,
  queues: [
    default: 10,
    notifications: 5,
    billing: 3,
    analytics: 5,
    maintenance: 2
  ],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       # Daily at 8am — check for upcoming formation/compliance deadlines
       {"0 8 * * *", MobileCarWash.Notifications.DeadlineReminderScheduler},
       # Every hour — clean up expired booking sessions
       {"0 * * * *", MobileCarWash.Booking.SessionCleanupWorker},
       # Daily at 2am — delete photos older than the retention period
       {"0 2 * * *", MobileCarWash.Operations.PhotoCleanupWorker},
       # Daily at 6am — create appointments from recurring schedules
       {"0 6 * * *", MobileCarWash.Scheduling.RecurringAppointmentScheduler},
       # Daily at 5am — generate the next 14 days of appointment blocks
       {"0 5 * * *", MobileCarWash.Scheduling.DailyBlockGeneratorWorker},
       # Every 5 minutes — close + optimize any :open block whose closes_at has passed
       {"*/5 * * * *", MobileCarWash.Scheduling.CloseExpiredBlocksWorker}
     ]}
  ]

# Photo retention: how many days before before/after/problem photos are deleted.
# S3 storage costs ~$0.023/GB/month; 90 days covers any reasonable dispute window.
config :mobile_car_wash, :photo_retention_days, 90

# Configure the endpoint
config :mobile_car_wash, MobileCarWashWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MobileCarWashWeb.ErrorHTML, json: MobileCarWashWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MobileCarWash.PubSub,
  live_view: [signing_salt: "D99pWWqn"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :mobile_car_wash, MobileCarWash.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  mobile_car_wash: [
    args:
      ~w(js/app.js js/ga-init.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  mobile_car_wash: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Admin emails (owner access to metrics dashboard)
# Override in runtime.exs for production
config :mobile_car_wash, :admin_emails, ["admin@mobilecarwash.com"]

# Photo storage — :local (dev) or :s3 (production, set in runtime.exs)
config :mobile_car_wash, :photo_storage, :local
config :mobile_car_wash, :s3_bucket, "mobile-car-wash-photos"
config :mobile_car_wash, :s3_region, "us-east-1"

# Stripe — dev placeholder, production key set in runtime.exs
config :stripity_stripe,
  api_key: "sk_test_placeholder",
  json_library: Jason

# Twilio SMS — dev/test defaults (no-ops). Production set in runtime.exs.
config :mobile_car_wash, :twilio,
  account_sid: nil,
  auth_token: nil,
  from_number: nil

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
