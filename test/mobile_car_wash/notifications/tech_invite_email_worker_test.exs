defmodule MobileCarWash.Notifications.TechInviteEmailWorkerTest do
  use MobileCarWash.DataCase, async: false
  use Oban.Testing, repo: MobileCarWash.Repo

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Notifications.TechInviteEmailWorker

  test "sends technician setup link email" do
    customer =
      Customer
      |> Ash.Changeset.for_create(:create_technician_invitee, %{
        email: "worker-invite-#{System.unique_integer([:positive])}@example.com",
        name: "Worker Invitee",
        phone: "+15125551100"
      })
      |> Ash.create!(authorize?: false)

    invite_url = "https://example.com/tech/invite/raw-token"
    expires_at = DateTime.add(DateTime.utc_now(), 7, :day)

    assert :ok =
             perform_job(TechInviteEmailWorker, %{
               "customer_id" => customer.id,
               "invite_url" => invite_url,
               "expires_at" => DateTime.to_iso8601(expires_at)
             })

    assert_received {:email, email}
    assert email.subject =~ "technician"
    assert email.text_body =~ invite_url
    assert email.html_body =~ invite_url
    assert Enum.any?(email.to, fn {_name, addr} -> addr == to_string(customer.email) end)
  end
end
