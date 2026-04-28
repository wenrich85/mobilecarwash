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
    referral_override = Keyword.get(opts, :referral_code, :unset)

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

    # Customer auto-generates a referral_code on register. Tests that need a
    # specific code or no code at all override here via force_change_attribute
    # (the public :update action accepts referral_code, but bypassing changes
    # keeps the test deterministic regardless of validations on that attr).
    case referral_override do
      :unset ->
        customer

      nil ->
        customer
        |> Ash.Changeset.for_update(:update, %{})
        |> Ash.Changeset.force_change_attribute(:referral_code, nil)
        |> Ash.update!(authorize?: false)

      code when is_binary(code) ->
        customer
        |> Ash.Changeset.for_update(:update, %{})
        |> Ash.Changeset.force_change_attribute(:referral_code, code)
        |> Ash.update!(authorize?: false)
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

  describe "next steps grid" do
    test "renders Download .ics button targeting /book/:id/calendar.ics", %{conn: conn} do
      customer = register_customer()
      {appt, _service, _address} = create_appointment(customer)

      {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

      assert html =~ "Download .ics"
      assert html =~ "/book/#{appt.id}/calendar.ics"
    end

    test "renders Google Calendar deep link", %{conn: conn} do
      customer = register_customer()
      {appt, service, _address} = create_appointment(customer)

      {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

      assert html =~ "calendar.google.com/calendar/render"
      assert html =~ URI.encode_www_form(service.name)
    end

    test "renders Outlook Web deep link", %{conn: conn} do
      customer = register_customer()
      {appt, _service, _address} = create_appointment(customer)

      {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

      assert html =~ "outlook.live.com/calendar/0/deeplink/compose"
    end

    test "renders Get directions link to Google Maps with encoded address", %{conn: conn} do
      customer = register_customer()
      {appt, _service, address} = create_appointment(customer)

      {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

      assert html =~ "maps/dir/?api=1"
      full_address = "#{address.street}, #{address.city}, #{address.state} #{address.zip}"
      assert html =~ URI.encode_www_form(full_address)
    end

    test "renders confirmation email status with customer email prefix", %{conn: conn} do
      customer = register_customer()
      {appt, _service, _address} = create_appointment(customer)

      {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

      assert html =~ "Sent to"
      local_part = customer.email |> to_string() |> String.split("@") |> hd()
      assert html =~ String.slice(local_part, 0, 2)
    end
  end

  describe "subscription upsell card" do
    test "renders for customer with no active subscription", %{conn: conn} do
      customer = register_customer()
      {appt, _service, _address} = create_appointment(customer)

      {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

      assert html =~ "Save 15% on every wash"
      assert html =~ ~p"/subscribe"
    end

    test "hides for customer with active subscription", %{conn: conn} do
      alias MobileCarWash.Billing.{Subscription, SubscriptionPlan}

      customer = register_customer()
      {appt, _service, _address} = create_appointment(customer)

      {:ok, plan} =
        SubscriptionPlan
        |> Ash.Changeset.for_create(:create, %{
          name: "Test Monthly",
          slug: "test-monthly-#{System.unique_integer([:positive])}",
          price_cents: 4_900,
          basic_washes_per_month: 2,
          deep_cleans_per_month: 0,
          deep_clean_discount_percent: 10
        })
        |> Ash.create()

      {:ok, _sub} =
        Subscription
        |> Ash.Changeset.for_create(:create, %{
          stripe_subscription_id: "sub_test_#{System.unique_integer([:positive])}",
          status: :active,
          current_period_start: Date.utc_today(),
          current_period_end: Date.add(Date.utc_today(), 30)
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
        |> Ash.Changeset.force_change_attribute(:plan_id, plan.id)
        |> Ash.create()

      {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

      refute html =~ "Save 15% on every wash"
    end
  end

  describe "referral card" do
    test "renders when customer has a referral code", %{conn: conn} do
      customer = register_customer(referral_code: "FRIEND123")
      {appt, _service, _address} = create_appointment(customer)

      {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

      assert html =~ "Give a friend $10 off"
      assert html =~ "FRIEND123"
    end

    test "hides when customer has no referral code", %{conn: conn} do
      customer = register_customer(referral_code: nil)
      {appt, _service, _address} = create_appointment(customer)

      assert customer.referral_code == nil
      {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

      refute html =~ "Give a friend $10 off"
    end
  end

  describe "footer area (happy path)" do
    test "renders review note + booking ID + back-to-home link", %{conn: conn} do
      customer = register_customer()
      {appt, _service, _address} = create_appointment(customer)

      {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

      assert html =~ "we&#39;ll text you a link to leave a review"
      assert html =~ "Booking ID:"
      assert html =~ to_string(appt.id)
      assert html =~ "← Back to home"
    end
  end

  describe "error state" do
    test "renders friendly heading + contact info when params are missing", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/book/success")

      assert html =~ "We couldn&#39;t find that booking."
      assert html =~ "If you completed payment, contact us"
      assert html =~ "mailto:hello@drivewaydetailcosa.com"
    end

    test "renders error state when id does not resolve", %{conn: conn} do
      bogus_id = Ecto.UUID.generate()

      {:ok, _view, html} = live(conn, ~p"/book/success?id=#{bogus_id}")

      assert html =~ "We couldn&#39;t find that booking."
    end

    test "renders error state when session_id does not resolve", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/book/success?session_id=cs_test_doesnotexist")

      assert html =~ "We couldn&#39;t find that booking."
    end
  end
end
