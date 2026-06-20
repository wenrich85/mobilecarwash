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

  # --- Subscription helpers ---

  defp create_covering_subscription(customer_id) do
    plan =
      MobileCarWash.Billing.SubscriptionPlan
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Plan",
        slug: "basic_plan_addons_#{:rand.uniform(100_000)}",
        price_cents: 9_000,
        basic_washes_per_month: 4,
        deep_cleans_per_month: 0,
        deep_clean_discount_percent: 0,
        description: "Covers basic washes"
      })
      |> Ash.create!()

    subscription =
      MobileCarWash.Billing.Subscription
      |> Ash.Changeset.for_create(:create, %{status: :active})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
      |> Ash.Changeset.force_change_attribute(:plan_id, plan.id)
      |> Ash.create!()

    subscription
  end

  defp create_basic_wash_service do
    # Must use the exact slug "basic_wash" so the pricing module recognises it
    # as covered by a basic_washes_per_month plan.
    MobileCarWash.Scheduling.ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic Wash",
      slug: "basic_wash",
      base_price_cents: 5_000,
      duration_minutes: 45
    })
    |> Ash.create!()
  rescue
    _ ->
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Query.filter(slug == "basic_wash")
      |> Ash.read!()
      |> hd()
  end

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

    test "inactive add-on id is never loaded, charged, or persisted", ctx do
      active = add_on("active_addon", 1_500)

      inactive =
        MobileCarWash.Scheduling.AddOn
        |> Ash.Changeset.for_create(:create, %{
          name: "Inactive AddOn",
          slug: "inactive_addon_#{:rand.uniform(100_000)}",
          price_cents: 2_000,
          active: true,
          sort_order: 1
        })
        |> Ash.create!()
        |> Ash.Changeset.for_update(:update, %{active: false})
        |> Ash.update!()

      {:ok, %{appointment: appt}} =
        Booking.create_booking(
          base_params(ctx) |> Map.put(:add_on_ids, [active.id, inactive.id])
        )

      # Only the active add-on ($15) should be added to the base ($50)
      assert appt.price_cents == 6_500

      appt = Ash.load!(appt, :appointment_add_ons)
      assert length(appt.appointment_add_ons) == 1
      assert hd(appt.appointment_add_ons).price_cents == 1_500
    end

    test "active subscription covers base service but add-ons are still charged and routed to checkout",
         ctx do
      # Service must use slug "basic_wash" so Pricing.subscription_discount_cents/3 recognises it
      service = create_basic_wash_service()
      subscription = create_covering_subscription(ctx.customer.id)

      wax = add_on("sub_wax", 1_500)
      interior = add_on("sub_interior", 1_000)

      params =
        base_params(ctx)
        |> Map.put(:service_type_id, service.id)
        |> Map.put(:subscription_id, subscription.id)
        |> Map.put(:add_on_ids, [wax.id, interior.id])

      {:ok, result} = Booking.create_booking(params)
      appt = result.appointment

      # Base $50 fully covered, add-ons ($15 + $10) are not — total must be $25
      assert appt.price_cents == 2_500

      # price_cents > 0 → Stripe checkout is initiated, NOT auto-confirmed
      # (price_cents == 0 path sets checkout_url: nil and status: :confirmed)
      assert appt.status == :pending

      # Join rows must exist for both add-ons
      appt = Ash.load!(appt, :appointment_add_ons)
      assert length(appt.appointment_add_ons) == 2
      assert Enum.sort(Enum.map(appt.appointment_add_ons, & &1.price_cents)) == [1_000, 1_500]
    end
  end
end
