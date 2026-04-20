defmodule MobileCarWash.Notifications.ReferralCreditWorkerTest do
  use MobileCarWash.DataCase, async: false
  use Oban.Testing, repo: MobileCarWash.Repo

  alias MobileCarWash.Notifications.ReferralCreditWorker
  alias MobileCarWash.Notifications.TwilioClientMock
  alias MobileCarWash.Accounts.Customer

  setup do
    TwilioClientMock.init()

    {:ok, referrer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "referrer-cred-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "The Referrer",
        phone: "+15125557777",
        sms_opt_in: true
      })
      |> Ash.create()

    {:ok, referee} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "referee-cred-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "New Customer"
      })
      |> Ash.create()

    %{referrer: referrer, referee: referee}
  end

  test "credits referrer $10 and sends SMS", %{referrer: referrer, referee: referee} do
    assert :ok =
             perform_job(ReferralCreditWorker, %{
               "referral_code" => referrer.referral_code,
               "referee_name" => referee.name
             })

    updated = Ash.get!(Customer, referrer.id, authorize?: false)
    assert updated.referral_credit_cents == 1000

    msgs = TwilioClientMock.messages_to("+15125557777")
    assert length(msgs) == 1
    {_to, body} = hd(msgs)
    assert body =~ "$10"
    assert body =~ "New Customer"
  end

  test "skips SMS when referrer has no phone or sms_opt_in off", %{
    referrer: referrer,
    referee: referee
  } do
    referrer
    |> Ash.Changeset.for_update(:update, %{sms_opt_in: false})
    |> Ash.update!(authorize?: false)

    assert :ok =
             perform_job(ReferralCreditWorker, %{
               "referral_code" => referrer.referral_code,
               "referee_name" => referee.name
             })

    # Credit still applied even without SMS
    updated = Ash.get!(Customer, referrer.id, authorize?: false)
    assert updated.referral_credit_cents == 1000

    # But no SMS sent
    assert TwilioClientMock.messages_to("+15125557777") == []
  end
end
