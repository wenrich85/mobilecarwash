defmodule MobileCarWash.MixProject do
  use Mix.Project

  def project do
    [
      app: :mobile_car_wash,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {MobileCarWash.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # Phoenix core
      {:phoenix, "~> 1.8.5"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},

      # Ash Framework — domain modeling & resource layer
      {:ash, "~> 3.21"},
      {:ash_postgres, "~> 2.8"},
      {:ash_phoenix, "~> 2.3"},
      {:ash_authentication, "~> 4.13"},
      {:ash_authentication_phoenix, "~> 2.15"},

      # Payments
      {:stripity_stripe, "~> 3.2"},

      # Background jobs
      {:oban, "~> 2.21"},

      # Security
      {:hammer, "~> 7.2"},
      {:cloak_ecto, "~> 1.3"},
      {:sobelow, "~> 0.14", only: :dev, runtime: false},
      {:mix_audit, "~> 2.1", only: :dev, runtime: false},

      # S3 file storage
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},

      # SAT solver (required by Ash policies)
      {:picosat_elixir, "~> 0.2"},

      # Testing (BDD)
      {:wallaby, "~> 0.30", only: :test, runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ash.setup", "assets.setup", "assets.build"],
      "ash.setup": ["ash.codegen", "ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ash.reset": ["ecto.drop", "ash.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind mobile_car_wash", "esbuild mobile_car_wash"],
      "assets.deploy": [
        "tailwind mobile_car_wash --minify",
        "esbuild mobile_car_wash --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
