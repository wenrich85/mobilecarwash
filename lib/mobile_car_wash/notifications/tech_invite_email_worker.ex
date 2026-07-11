defmodule MobileCarWash.Notifications.TechInviteEmailWorker do
  @moduledoc """
  Sends the one-time technician account setup link created by an admin.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Notifications.Email

  require Logger

  @impl true
  def perform(%Oban.Job{
        args: %{
          "customer_id" => customer_id,
          "invite_url" => invite_url,
          "expires_at" => expires_at
        }
      }) do
    with {:ok, customer} <- Ash.get(Customer, customer_id, authorize?: false),
         {:ok, expires_at, _offset} <- DateTime.from_iso8601(expires_at),
         {:ok, _email} <-
           customer
           |> Email.tech_invite(invite_url, expires_at)
           |> MobileCarWash.Mailer.deliver() do
      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to deliver technician invite email: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
