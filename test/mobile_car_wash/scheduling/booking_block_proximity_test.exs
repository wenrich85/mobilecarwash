defmodule MobileCarWash.Scheduling.BookingBlockProximityTest do
  @moduledoc """
  When a customer books into a block that already contains appointments,
  their address must be within the admin-configured drive-time threshold
  of at least one existing appointment in that block. Empty blocks always
  accept (first appointment seeds the block).

  Uses the real Haversine calculation with the default 30 mph + 1.4
  detour factor. San Antonio-area coords chosen so deltas are well above
  and below 20 minutes of drive time.
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Scheduling.{
    AppointmentBlock,
    Booking,
    SchedulingSettings,
    ServiceType
  }

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Address, Vehicle}

  # ~1.5 miles apart; well within 20 min drive
  @near_a {29.6500, -98.4200}
  @near_b {29.6600, -98.4100}
  # ~20+ miles away from @near_a; well outside 20 min
  @far {29.9500, -98.1200}

  setup do
    # Fresh default: 20 min
    {:ok, _} = SchedulingSettings.update(%{max_intra_block_drive_minutes: 20})

    {:ok, service_type} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "proximity-#{System.unique_integer([:positive])}",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, technician} =
      MobileCarWash.Operations.Technician
      |> Ash.Changeset.for_create(:create, %{
        name: "Proximity Tech",
        phone: "+15125550000",
        active: true
      })
      |> Ash.create()

    starts_at = DateTime.add(DateTime.utc_now(), 3 * 24 * 3600, :second)

    {:ok, block} =
      AppointmentBlock
      |> Ash.Changeset.for_create(:create, %{
        starts_at: starts_at,
        ends_at: DateTime.add(starts_at, 4 * 3600, :second),
        closes_at: DateTime.add(starts_at, 3600, :second),
        capacity: 3,
        service_type_id: service_type.id,
        technician_id: technician.id,
        status: :open
      })
      |> Ash.create()

    %{block: block, service_type: service_type}
  end

  defp make_customer_with_address(coords, opts \\ []) do
    {lat, lng} = coords

    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "prox-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: opts[:name] || "Proximity Test",
        phone: "+15125559#{:rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")}"
      })
      |> Ash.create()

    {:ok, vehicle} =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Honda", model: "Civic"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      Address
      |> Ash.Changeset.for_create(:create, %{
        street: "#{:rand.uniform(9999)} Test St",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.Changeset.force_change_attribute(:latitude, lat)
      |> Ash.Changeset.force_change_attribute(:longitude, lng)
      |> Ash.create()

    %{customer: customer, vehicle: vehicle, address: address}
  end

  defp book_into_block(block, service_type, %{customer: c, vehicle: v, address: a}) do
    Booking.create_booking(%{
      customer_id: c.id,
      vehicle_id: v.id,
      address_id: a.id,
      service_type_id: service_type.id,
      appointment_block_id: block.id,
      scheduled_at: block.starts_at
    })
  end

  describe "first appointment in an empty block" do
    test "is always accepted regardless of distance from shop origin",
         %{block: block, service_type: service_type} do
      fixture = make_customer_with_address(@far)
      assert {:ok, _} = book_into_block(block, service_type, fixture)
    end
  end

  describe "subsequent appointments" do
    test "accepted when within 20 min drive of an existing appointment",
         %{block: block, service_type: service_type} do
      # Seed the block
      seed = make_customer_with_address(@near_a)
      {:ok, _} = book_into_block(block, service_type, seed)

      nearby = make_customer_with_address(@near_b, name: "Nearby")
      assert {:ok, _} = book_into_block(block, service_type, nearby)
    end

    test "rejected when outside 20 min drive of every existing appointment",
         %{block: block, service_type: service_type} do
      seed = make_customer_with_address(@near_a)
      {:ok, _} = book_into_block(block, service_type, seed)

      far = make_customer_with_address(@far, name: "Far Away")
      assert {:error, :block_too_far} = book_into_block(block, service_type, far)
    end

    test "accepted when close to ANY of the block's appointments (not just the first)",
         %{block: block, service_type: service_type} do
      # Seed with a far address, then add a near one, then try another near one.
      # The third should match the second, not the first.
      seed_far = make_customer_with_address(@far)
      # To test this we first bump the threshold so the seed+near can coexist.
      {:ok, _} = SchedulingSettings.update(%{max_intra_block_drive_minutes: 120})
      {:ok, _} = book_into_block(block, service_type, seed_far)

      near_a = make_customer_with_address(@near_a, name: "Anchor Near A")
      {:ok, _} = book_into_block(block, service_type, near_a)

      # Drop threshold back down — the third customer is far from seed_far but
      # close to near_a, so it should still be accepted.
      {:ok, _} = SchedulingSettings.update(%{max_intra_block_drive_minutes: 20})
      near_b = make_customer_with_address(@near_b, name: "Third Near B")
      assert {:ok, _} = book_into_block(block, service_type, near_b)
    end
  end

  describe "admin-configurable threshold" do
    test "tightening the threshold rejects a booking that would have fit",
         %{block: block, service_type: service_type} do
      seed = make_customer_with_address(@near_a)
      {:ok, _} = book_into_block(block, service_type, seed)

      # The two "near" coords are ~1.5 mi apart — roughly 3 min drive.
      # Drop the threshold below that to force a rejection.
      {:ok, _} = SchedulingSettings.update(%{max_intra_block_drive_minutes: 1})

      nearby = make_customer_with_address(@near_b, name: "Would-Fit-At-20")
      assert {:error, :block_too_far} = book_into_block(block, service_type, nearby)
    end
  end
end
