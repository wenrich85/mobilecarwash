defmodule MobileCarWash.Scheduling.BookingAddOnsTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Scheduling.Booking

  require Ash.Query

  # --- Test Helpers ---

  defp create_customer do
    MobileCarWash.Accounts.Customer
    |> Ash.Changeset.for_create(:create_guest, %{
      email: "addons-test-#{:rand.uniform(100_000)}@example.com",
      name: "AddOns Test",
      phone: "512-555-0001"
    })
    |> Ash.create!()
  end

  defp create_service_type do
    MobileCarWash.Scheduling.ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Test Basic Wash",
      slug: "basic_wash_addons_#{:rand.uniform(100_000)}",
      base_price_cents: 5000,
      duration_minutes: 45
    })
    |> Ash.create!()
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
    # Fixed far-future Thursday at 11am — different from booking_test to avoid conflicts
    {:ok, dt} = DateTime.new(~D[2030-07-11], ~T[11:00:00])
    dt
  end

  # Build a car-sized booking params map — yields $5000 base (1.0x on 5000 base)
  defp base_params(ctx) do
    %{
      customer_id: ctx.customer.id,
      service_type_id: ctx.service.id,
      vehicle_id: ctx.vehicle.id,
      address_id: ctx.address.id,
      scheduled_at: tomorrow_slot(),
      subscription_id: nil
    }
  end

  # Create an active add-on with the given slug and price
  defp add_on(slug, price_cents) do
    MobileCarWash.Scheduling.AddOn
    |> Ash.Changeset.for_create(:create, %{
      name: "Test #{slug}",
      slug: "#{slug}_#{:rand.uniform(100_000)}",
      description: "Test add-on",
      price_cents: price_cents,
      active: true,
      sort_order: 1
    })
    |> Ash.create!()
  end

  # --- Setup ---

  setup do
    customer = create_customer()
    service = create_service_type()
    vehicle = create_vehicle(customer.id, :car)
    address = create_address(customer.id)

    {:ok, customer: customer, service: service, vehicle: vehicle, address: address}
  end

  # --- Tests ---

  describe "create_booking/1 with add-ons" do
    test "folds add-on total into price and persists join rows", ctx do
      wax = add_on("wax_shine", 1_500)
      pet = add_on("pet_hair", 1_000)

      {:ok, %{appointment: appt}} =
        Booking.create_booking(base_params(ctx) |> Map.put(:add_on_ids, [wax.id, pet.id]))

      # Car basic wash $50 base + $25 add-ons = $75
      assert appt.price_cents == 7_500

      appt = Ash.load!(appt, :appointment_add_ons)
      assert length(appt.appointment_add_ons) == 2
      assert Enum.sort(Enum.map(appt.appointment_add_ons, & &1.price_cents)) == [1_000, 1_500]
    end

    test "no add_on_ids leaves price unchanged and creates no join rows", ctx do
      {:ok, %{appointment: appt}} = Booking.create_booking(base_params(ctx))
      assert appt.price_cents == 5_000
      appt = Ash.load!(appt, :appointment_add_ons)
      assert appt.appointment_add_ons == []
    end
  end
end
