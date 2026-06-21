defmodule MobileCarWash.Scheduling.BookingTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Scheduling.Booking
  alias MobileCarWash.Billing.Pricing

  require Ash.Query

  # --- Test Helpers ---

  defp create_customer(attrs \\ %{}) do
    email = attrs[:email] || "booking-test-#{:rand.uniform(100_000)}@example.com"
    name = attrs[:name] || "Booking Test"

    MobileCarWash.Accounts.Customer
    |> Ash.Changeset.for_create(:create_guest, %{email: email, name: name, phone: "512-555-0000"})
    |> Ash.create!()
  end

  defp create_service_type(slug \\ "basic_wash") do
    existing =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Query.filter(slug == ^slug)
      |> Ash.read!()

    case existing do
      [st | _] ->
        st

      [] ->
        MobileCarWash.Scheduling.ServiceType
        |> Ash.Changeset.for_create(:create, %{
          name: "Test #{slug}",
          slug: "#{slug}_#{:rand.uniform(100_000)}",
          base_price_cents: 5000,
          duration_minutes: 45
        })
        |> Ash.create!()
    end
  end

  defp create_vehicle(customer_id, size \\ :car) do
    MobileCarWash.Fleet.Vehicle
    |> Ash.Changeset.for_create(:create, %{make: "Test", model: "Car", size: size})
    |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
    |> Ash.create!()
  end

  defp create_address(customer_id) do
    MobileCarWash.Fleet.Address
    |> Ash.Changeset.for_create(:create, %{
      street: "123 Test St",
      city: "Austin",
      state: "TX",
      zip: "78701"
    })
    |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
    |> Ash.create!()
  end

  defp tomorrow_slot do
    # Fixed far-future Wednesday at 10am — avoids conflicts and Sundays
    {:ok, dt} = DateTime.new(~D[2030-07-10], ~T[10:00:00])
    dt
  end

  defp create_add_on(attrs \\ []) do
    price_cents = Keyword.get(attrs, :price_cents, 1_000)
    slug = "addon-#{:rand.uniform(100_000)}"

    MobileCarWash.Scheduling.AddOn
    |> Ash.Changeset.for_create(:create, %{
      name: "Test Add-On",
      slug: slug,
      price_cents: price_cents,
      active: true
    })
    |> Ash.create!()
  end

  defp grant_free_wash(customer) do
    punches = MobileCarWash.Loyalty.punches_per_reward()
    Enum.each(1..punches, fn _ -> MobileCarWash.Loyalty.add_punch(customer.id) end)
  end

  # --- Tests ---

  describe "create_booking/1 — full flow" do
    test "creates appointment with car (1.0x pricing)" do
      customer = create_customer()
      service = create_service_type()
      vehicle = create_vehicle(customer.id, :car)
      address = create_address(customer.id)

      {:ok, %{appointment: appt}} =
        Booking.create_booking(%{
          customer_id: customer.id,
          service_type_id: service.id,
          vehicle_id: vehicle.id,
          address_id: address.id,
          scheduled_at: tomorrow_slot(),
          subscription_id: nil
        })

      assert appt.price_cents == Pricing.calculate(service.base_price_cents, :car)
      assert appt.status == :pending
      assert appt.duration_minutes == service.duration_minutes
    end

    test "creates appointment with SUV/Van (1.2x pricing)" do
      customer = create_customer()
      service = create_service_type()
      vehicle = create_vehicle(customer.id, :suv_van)
      address = create_address(customer.id)

      {:ok, %{appointment: appt}} =
        Booking.create_booking(%{
          customer_id: customer.id,
          service_type_id: service.id,
          vehicle_id: vehicle.id,
          address_id: address.id,
          scheduled_at: tomorrow_slot(),
          subscription_id: nil
        })

      expected = Pricing.calculate(service.base_price_cents, :suv_van)
      assert appt.price_cents == expected
      assert expected == 6000
    end

    test "creates appointment with pickup (1.5x pricing)" do
      customer = create_customer()
      service = create_service_type()
      vehicle = create_vehicle(customer.id, :pickup)
      address = create_address(customer.id)

      {:ok, %{appointment: appt}} =
        Booking.create_booking(%{
          customer_id: customer.id,
          service_type_id: service.id,
          vehicle_id: vehicle.id,
          address_id: address.id,
          scheduled_at: tomorrow_slot(),
          subscription_id: nil
        })

      expected = Pricing.calculate(service.base_price_cents, :pickup)
      assert appt.price_cents == expected
      assert expected == 7500
    end

    test "creates payment record with correct amount" do
      customer = create_customer()
      service = create_service_type()
      vehicle = create_vehicle(customer.id, :pickup)
      address = create_address(customer.id)

      {:ok, %{appointment: appt}} =
        Booking.create_booking(%{
          customer_id: customer.id,
          service_type_id: service.id,
          vehicle_id: vehicle.id,
          address_id: address.id,
          scheduled_at: tomorrow_slot(),
          subscription_id: nil
        })

      # Verify payment was created
      payments =
        MobileCarWash.Billing.Payment
        |> Ash.Query.filter(appointment_id == ^appt.id)
        |> Ash.read!()

      assert length(payments) == 1
      [payment] = payments
      assert payment.amount_cents == appt.price_cents
      assert payment.status == :pending
    end

    test "rejects booking with vehicle not owned by customer" do
      customer1 = create_customer(%{email: "owner-#{:rand.uniform(100_000)}@test.com"})
      customer2 = create_customer(%{email: "other-#{:rand.uniform(100_000)}@test.com"})
      service = create_service_type()
      vehicle = create_vehicle(customer1.id)
      address = create_address(customer2.id)

      result =
        Booking.create_booking(%{
          customer_id: customer2.id,
          service_type_id: service.id,
          vehicle_id: vehicle.id,
          address_id: address.id,
          scheduled_at: tomorrow_slot(),
          subscription_id: nil
        })

      assert {:error, :vehicle_not_owned} = result
    end

    test "rejects booking for unavailable time slot" do
      customer = create_customer()
      service = create_service_type()
      vehicle = create_vehicle(customer.id)
      address = create_address(customer.id)

      # Book the first slot
      {:ok, _} =
        Booking.create_booking(%{
          customer_id: customer.id,
          service_type_id: service.id,
          vehicle_id: vehicle.id,
          address_id: address.id,
          scheduled_at: tomorrow_slot(),
          subscription_id: nil
        })

      # Try booking the same slot — should fail
      customer2 = create_customer(%{email: "dupe-#{:rand.uniform(100_000)}@test.com"})
      vehicle2 = create_vehicle(customer2.id)
      address2 = create_address(customer2.id)

      result =
        Booking.create_booking(%{
          customer_id: customer2.id,
          service_type_id: service.id,
          vehicle_id: vehicle2.id,
          address_id: address2.id,
          scheduled_at: tomorrow_slot(),
          subscription_id: nil
        })

      assert {:error, :slot_unavailable} = result
    end

    test "add-on price scales with vehicle size in the charged total" do
      # pickup (1.5x): base 5000 * 1.5 = 7500; add-on 1000 * 1.5 = 1500; total 9000
      customer = create_customer()
      service = create_service_type()
      vehicle = create_vehicle(customer.id, :pickup)
      address = create_address(customer.id)
      add_on = create_add_on(price_cents: 1_000)

      {:ok, %{appointment: appt}} =
        Booking.create_booking(%{
          customer_id: customer.id,
          service_type_id: service.id,
          vehicle_id: vehicle.id,
          address_id: address.id,
          scheduled_at: tomorrow_slot(),
          subscription_id: nil,
          add_on_ids: [add_on.id]
        })

      assert appt.price_cents == 9_000
    end

    test "a valid referral code reduces the charged total" do
      customer = create_customer()
      # Every customer created via :create_guest gets a referral_code auto-generated
      # in the Customer resource changes block — no extra setup needed.
      referrer = create_customer(%{email: "referrer-#{:rand.uniform(100_000)}@example.com"})
      assert referrer.referral_code != nil

      service = create_service_type()
      vehicle = create_vehicle(customer.id, :car)
      address = create_address(customer.id)

      {:ok, %{appointment: appt}} =
        Booking.create_booking(%{
          customer_id: customer.id,
          service_type_id: service.id,
          vehicle_id: vehicle.id,
          address_id: address.id,
          scheduled_at: tomorrow_slot(),
          subscription_id: nil,
          referral_code: referrer.referral_code
        })

      # base 5000; referral discount $10 (1000 cents) → 4000
      assert appt.price_cents < 5_000
      assert appt.referral_code_used == referrer.referral_code
    end

    test "loyalty redemption zeroes a covered basic wash and consumes a free wash" do
      customer = create_customer()
      service = create_service_type()
      vehicle = create_vehicle(customer.id, :car)
      address = create_address(customer.id)

      grant_free_wash(customer)

      {:ok, card_before} = MobileCarWash.Loyalty.get_or_create_card(customer.id)
      assert MobileCarWash.Loyalty.available_free_washes(card_before) == 1

      {:ok, %{appointment: appt}} =
        Booking.create_booking(%{
          customer_id: customer.id,
          service_type_id: service.id,
          vehicle_id: vehicle.id,
          address_id: address.id,
          scheduled_at: tomorrow_slot(),
          subscription_id: nil,
          loyalty_redeem: true
        })

      assert appt.price_cents == 0

      {:ok, card_after} = MobileCarWash.Loyalty.get_or_create_card(customer.id)
      assert MobileCarWash.Loyalty.available_free_washes(card_after) == 0
    end
  end
end
