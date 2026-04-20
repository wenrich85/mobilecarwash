defmodule MobileCarWashWeb.HealthController do
  @moduledoc """
  Liveness + readiness probes.

  Two distinct endpoints — same pattern Kubernetes and DigitalOcean
  App Platform both use:

    * `/health` (liveness) — the BEAM is up and the router is
      responding. A failing response here triggers a restart.
      Cheap, no dependencies checked.

    * `/ready` (readiness) — the app can serve real traffic: DB is
      reachable. A failing response here takes the pod out of the
      load balancer rotation but doesn't restart.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Repo

  def live(conn, _params) do
    conn
    |> put_status(200)
    |> json(%{
      status: "ok",
      version: version(),
      at: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  def ready(conn, _params) do
    db_status = check_db()

    http_status = if db_status == "ok", do: 200, else: 503

    conn
    |> put_status(http_status)
    |> json(%{
      status: if(http_status == 200, do: "ready", else: "not_ready"),
      checks: %{database: db_status},
      version: version(),
      at: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  defp check_db do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", [], timeout: 2_000) do
      {:ok, _} -> "ok"
      _ -> "down"
    end
  rescue
    _ -> "down"
  end

  defp version do
    Application.spec(:mobile_car_wash, :vsn)
    |> to_string()
  end
end
