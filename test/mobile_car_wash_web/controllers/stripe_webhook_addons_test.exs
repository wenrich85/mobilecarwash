defmodule MobileCarWashWeb.StripeWebhookAddonsTest do
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Scheduling.{AppointmentServices, AppointmentAddOn, AddOn, Appointment}
  alias MobileCarWash.Billing.Payment

  require Ash.Query

  test "complete_addon_checkout attaches add-ons and marks the payment succeeded" do
    # minimal appointment + add-on + pending payment with a checkout session id
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "wh-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "WH",
        phone: "+15125550000"
      })
      |> Ash.create()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic",
        slug: "wh-#{System.unique_integer([:positive])}",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry", year: 2021})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.Changeset.force_change_attribute(:size, :car)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{
        street: "1 Main",
        city: "SA",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, appt} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        scheduled_at: DateTime.add(DateTime.utc_now(), 48 * 3600),
        price_cents: 5_000,
        duration_minutes: 45,
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service_type.id
      })
      |> Ash.create()

    {:ok, addon} =
      AddOn
      |> Ash.Changeset.for_create(:create, %{
        name: "Wax",
        slug: "wax-#{System.unique_integer([:positive])}",
        price_cents: 2_000
      })
      |> Ash.create()

    {:ok, payment} =
      Payment
      |> Ash.Changeset.for_create(:create, %{amount_cents: 2_000, status: :pending})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.Changeset.force_change_attribute(:appointment_id, appt.id)
      |> Ash.Changeset.force_change_attribute(:stripe_checkout_session_id, "cs_test_addon_1")
      |> Ash.create()

    session = %{
      id: "cs_test_addon_1",
      payment_intent: "pi_test_addon_1",
      metadata: %{
        "kind" => "appointment_addons",
        "appointment_id" => appt.id,
        "add_on_ids" => addon.id
      }
    }

    assert :ok = AppointmentServices.complete_addon_checkout(session)

    assert [%{price_cents: 2_000}] =
             AppointmentAddOn |> Ash.Query.filter(appointment_id == ^appt.id) |> Ash.read!()

    assert Ash.get!(Appointment, appt.id).price_cents == 7_000
    assert Ash.get!(Payment, payment.id).status == :succeeded
  end
end
