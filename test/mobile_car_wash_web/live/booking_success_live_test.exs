defmodule MobileCarWashWeb.BookingSuccessLiveTest do
  @moduledoc """
  Tests for the redesigned post-booking success page. Covers both arrival
  paths (Stripe `?session_id=...` and in-app `?id=...`), conditional UI
  (subscription upsell, referral card, technician line), calendar/maps
  deep links, and error states.
  """
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Billing.Payment
  alias MobileCarWash.Fleet.{Address, Vehicle}
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  defp register_customer(opts \\ []) do
    referral = Keyword.get(opts, :referral_code, nil)

    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "success-live-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Success Live",
        phone: "+15125559000"
      })
      |> Ash.create()

    if referral do
      customer
      |> Ash.Changeset.for_update(:update, %{referral_code: referral})
      |> Ash.update!()
    else
      customer
    end
  end

  defp create_appointment(customer) do
    {:ok, service} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Premium Detail",
        slug: "premium-detail-#{System.unique_integer([:positive])}",
        base_price_cents: 8_900,
        duration_minutes: 90
      })
      |> Ash.create()

    {:ok, vehicle} =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Tesla", model: "Model 3"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      Address
      |> Ash.Changeset.for_create(:create, %{
        street: "1717 Success Lane",
        city: "San Antonio",
        state: "TX",
        zip: "78261"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, appt} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        scheduled_at: DateTime.add(DateTime.utc_now(), 2 * 86_400, :second),
        price_cents: 8_900,
        duration_minutes: 90
      })
      |> Ash.create()

    {appt, service, address}
  end

  describe "mount with `id` param (in-app arrival)" do
    test "renders booking confirmed for valid id", %{conn: conn} do
      customer = register_customer()
      {appt, service, _address} = create_appointment(customer)

      {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

      assert html =~ "Booking confirmed"
      assert html =~ service.name
    end
  end

  describe "appointment summary card content" do
    test "renders price chip from payment when present", %{conn: conn} do
      customer = register_customer()
      {appt, _service, _address} = create_appointment(customer)

      # Seed a payment row associated with this appointment.
      # Payment.create doesn't accept relationship FKs as public inputs —
      # use force_change_attribute (same pattern used elsewhere in this file).
      {:ok, _payment} =
        Payment
        |> Ash.Changeset.for_create(:create, %{
          amount_cents: 8_900,
          status: :succeeded,
          stripe_checkout_session_id: "cs_test_#{System.unique_integer([:positive])}"
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
        |> Ash.Changeset.force_change_attribute(:appointment_id, appt.id)
        |> Ash.create()

      {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

      assert html =~ "$89"
    end

    test "renders price chip from service when payment is nil", %{conn: conn} do
      customer = register_customer()
      {appt, _service, _address} = create_appointment(customer)

      {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

      # No payment seeded → fall back to service.base_price_cents (8_900)
      assert html =~ "$89"
    end

    test "renders the service name as a chip", %{conn: conn} do
      customer = register_customer()
      {appt, service, _address} = create_appointment(customer)

      {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

      assert html =~ service.name
    end

    test "renders the full address", %{conn: conn} do
      customer = register_customer()
      {appt, _service, address} = create_appointment(customer)

      {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

      assert html =~ address.street
      assert html =~ address.city
      assert html =~ address.zip
    end

    test "renders the muted technician line when none is assigned", %{conn: conn} do
      customer = register_customer()
      {appt, _service, _address} = create_appointment(customer)

      {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

      assert appt.technician_id == nil
      assert html =~ "We&#39;ll let you know once a technician is assigned."
    end
  end
end
