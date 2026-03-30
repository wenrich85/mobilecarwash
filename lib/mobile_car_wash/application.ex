defmodule MobileCarWash.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MobileCarWashWeb.Telemetry,
      MobileCarWash.Repo,
      {DNSCluster, query: Application.get_env(:mobile_car_wash, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MobileCarWash.PubSub},
      # Oban background job processor
      {Oban, Application.fetch_env!(:mobile_car_wash, Oban)},
      # Start to serve requests, typically the last entry
      MobileCarWashWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MobileCarWash.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MobileCarWashWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
