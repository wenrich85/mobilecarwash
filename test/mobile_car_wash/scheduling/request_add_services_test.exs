defmodule MobileCarWash.Scheduling.RequestAddServicesTest do
  use MobileCarWash.DataCase, async: false

  import Swoosh.TestAssertions

  alias MobileCarWash.Scheduling.{AppointmentServices, AppointmentAddOn, AddOn, Appointment}
  alias MobileCarWash.Billing.Payment

  require Ash.Query

  # Drain all pending emails (e.g. the registration verification email) so
  # assert_email_sent below lands only on the payment receipt.
  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end

  # hours_out: how far in the future to schedule; cus: stripe_customer_id scenario
  defp setup_appt(hours_out, cus) do
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ras-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "RAS",
        phone: "+15125550000"
      })
      |> Ash.Changeset.force_change_attribute(:stripe_customer_id, cus)
      |> Ash.create()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic",
        slug: "ras-#{System.unique_integer([:positive])}",
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

    {:ok, appointment} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        scheduled_at: DateTime.add(DateTime.utc_now(), hours_out * 3600),
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

    %{appointment: appointment, addon: addon}
  end

  test "rejects an appointment inside the 12h cutoff" do
    %{appointment: appt, addon: addon} = setup_appt(6, "cus_test_1")
    assert {:error, :not_editable} = AppointmentServices.request_add_services(appt, [addon.id])
  end

  test "card success: attaches add-ons, bumps price, records a succeeded payment + receipt" do
    %{appointment: appt, addon: addon} = setup_appt(48, "cus_test_2")
    flush_emails()

    assert {:ok, :charged} = AppointmentServices.request_add_services(appt, [addon.id])

    updated = Ash.get!(Appointment, appt.id)
    assert updated.price_cents == 7_000

    [row] = AppointmentAddOn |> Ash.Query.filter(appointment_id == ^appt.id) |> Ash.read!()
    assert row.price_cents == 2_000

    [payment] = Payment |> Ash.Query.filter(appointment_id == ^appt.id) |> Ash.read!()
    assert payment.status == :succeeded
    assert payment.amount_cents == 2_000

    assert_email_sent(subject: "Payment Receipt — $20.00")
  end

  test "card failure: returns a checkout_url and attaches nothing" do
    %{appointment: appt, addon: addon} = setup_appt(48, "cus_decline_3")

    assert {:ok, "https://checkout.stripe.com/pay/" <> _} =
             AppointmentServices.request_add_services(appt, [addon.id])

    assert [] = AppointmentAddOn |> Ash.Query.filter(appointment_id == ^appt.id) |> Ash.read!()
    assert Ash.get!(Appointment, appt.id).price_cents == 5_000
  end
end
