defmodule MobileCarWash.Billing.PaymentManualTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Billing.Payment
  alias MobileCarWash.Accounts.Customer

  defp customer do
    Customer
    |> Ash.Changeset.for_create(:create_guest, %{
      name: "Comp Client",
      email: "comp-#{System.unique_integer([:positive])}@test.com",
      phone: "+15125550111"
    })
    |> Ash.create!(authorize?: false)
  end

  test "record_manual for a comp records full value, zero collected, succeeded" do
    cust = customer()

    {:ok, payment} =
      Payment
      |> Ash.Changeset.for_create(:record_manual, %{
        amount_cents: 5000,
        collected_cents: 0,
        comped: true,
        comp_reason: "VIP friend"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, cust.id)
      |> Ash.create(authorize?: false)

    assert payment.amount_cents == 5000
    assert payment.collected_cents == 0
    assert payment.comped == true
    assert payment.comp_reason == "VIP friend"
    assert payment.status == :succeeded
    assert payment.paid_at
  end

  test "record_manual requires a reason when comped" do
    cust = customer()

    {:error, error} =
      Payment
      |> Ash.Changeset.for_create(:record_manual, %{
        amount_cents: 5000,
        collected_cents: 0,
        comped: true
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, cust.id)
      |> Ash.create(authorize?: false)

    assert Exception.message(error) =~ "comp_reason"
  end

  test "record_manual for a paid manual booking records the collected amount" do
    cust = customer()

    {:ok, payment} =
      Payment
      |> Ash.Changeset.for_create(:record_manual, %{
        amount_cents: 5000,
        collected_cents: 5000,
        comped: false
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, cust.id)
      |> Ash.create(authorize?: false)

    assert payment.comped == false
    assert payment.collected_cents == 5000
    assert payment.status == :succeeded
  end
end
