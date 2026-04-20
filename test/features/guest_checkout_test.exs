defmodule MobileCarWash.Features.GuestCheckoutTest do
  @moduledoc """
  BDD Feature: Guest checkout — one-time customers book without creating an account

  As a first-time customer
  I want to book a car wash without creating a password
  So that I can get my car cleaned with minimal friction
  """
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Vehicle, Address}
  alias MobileCarWash.Scheduling.{ServiceType, Booking, Availability}
  alias MobileCarWash.Billing.{Payment, Pricing}

  require Ash.Query

  defp create_service do
    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic Wash",
      slug: "guest_test_#{:rand.uniform(100_000)}",
      base_price_cents: 5000,
      duration_minutes: 45
    })
    |> Ash.create!()
  end

  describe "guest customer creation" do
    test "creates a guest customer without password" do
      {:ok, guest} =
        Customer
        |> Ash.Changeset.for_create(:create_guest, %{
          email: "guest-#{:rand.uniform(100_000)}@example.com",
          name: "Jane Guest",
          phone: "512-555-1234"
        })
        |> Ash.create()

      assert guest.role == :guest
      assert guest.name == "Jane Guest"
      assert guest.hashed_password == nil
    end

    test "rejects guest with duplicate email" do
      email = "dup-guest-#{:rand.uniform(100_000)}@example.com"

      {:ok, _} =
        Customer
        |> Ash.Changeset.for_create(:create_guest, %{email: email, name: "First"})
        |> Ash.create()

      {:error, _} =
        Customer
        |> Ash.Changeset.for_create(:create_guest, %{email: email, name: "Second"})
        |> Ash.create()
    end
  end

  describe "guest vehicle creation" do
    test "creates vehicle linked to guest customer via force_change_attribute" do
      {:ok, guest} =
        Customer
        |> Ash.Changeset.for_create(:create_guest, %{
          email: "veh-test-#{:rand.uniform(100_000)}@example.com",
          name: "Vehicle Test"
        })
        |> Ash.create()

      {:ok, vehicle} =
        Vehicle
        |> Ash.Changeset.for_create(:create, %{make: "Honda", model: "Civic", size: :car})
        |> Ash.Changeset.force_change_attribute(:customer_id, guest.id)
        |> Ash.create()

      assert vehicle.customer_id == guest.id
      assert vehicle.size == :car
    end

    test "creates vehicle with all size types" do
      {:ok, guest} =
        Customer
        |> Ash.Changeset.for_create(:create_guest, %{
          email: "sizes-#{:rand.uniform(100_000)}@example.com",
          name: "Size Test"
        })
        |> Ash.create()

      for size <- [:car, :suv_van, :pickup] do
        {:ok, v} =
          Vehicle
          |> Ash.Changeset.for_create(:create, %{make: "Test", model: "#{size}", size: size})
          |> Ash.Changeset.force_change_attribute(:customer_id, guest.id)
          |> Ash.create()

        assert v.size == size
      end
    end
  end

  describe "guest address creation" do
    test "creates address linked to guest customer" do
      {:ok, guest} =
        Customer
        |> Ash.Changeset.for_create(:create_guest, %{
          email: "addr-#{:rand.uniform(100_000)}@example.com",
          name: "Addr Test"
        })
        |> Ash.create()

      {:ok, address} =
        Address
        |> Ash.Changeset.for_create(:create, %{
          street: "999 Guest Ln",
          city: "Austin",
          state: "TX",
          zip: "78701"
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, guest.id)
        |> Ash.create()

      assert address.customer_id == guest.id
      assert address.state == "TX"
    end
  end

  describe "full guest booking flow end-to-end" do
    test "guest can complete entire booking with pickup truck pricing" do
      service = create_service()

      # Step 1: Guest checkout
      {:ok, guest} =
        Customer
        |> Ash.Changeset.for_create(:create_guest, %{
          email: "e2e-#{:rand.uniform(100_000)}@example.com",
          name: "E2E Guest",
          phone: "512-555-9999"
        })
        |> Ash.create()

      assert guest.role == :guest

      # Step 2: Add vehicle (pickup = 1.5x)
      {:ok, vehicle} =
        Vehicle
        |> Ash.Changeset.for_create(:create, %{
          make: "Ford",
          model: "F-150",
          year: 2024,
          size: :pickup
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, guest.id)
        |> Ash.create()

      # Step 3: Add address
      {:ok, address} =
        Address
        |> Ash.Changeset.for_create(:create, %{
          street: "100 E2E Blvd",
          city: "Austin",
          state: "TX",
          zip: "78745"
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, guest.id)
        |> Ash.create()

      # Step 4: Check availability
      tomorrow = Date.new!(2030, 8, 7)
      slots = Availability.available_slots(tomorrow, service.duration_minutes, [])
      assert length(slots) > 0
      selected_slot = hd(slots)

      # Step 5: Book
      {:ok, %{appointment: appt}} =
        Booking.create_booking(%{
          customer_id: guest.id,
          service_type_id: service.id,
          vehicle_id: vehicle.id,
          address_id: address.id,
          scheduled_at: selected_slot.starts_at,
          subscription_id: nil
        })

      # Verify pricing: $50 base * 1.5 pickup = $75
      expected_price = Pricing.calculate(service.base_price_cents, :pickup)
      assert appt.price_cents == expected_price
      assert expected_price == 7500

      # Verify appointment data
      assert appt.status == :pending
      assert appt.customer_id == guest.id
      assert appt.vehicle_id == vehicle.id
      assert appt.address_id == address.id
      assert appt.duration_minutes == service.duration_minutes

      # Verify payment record
      payments = Payment |> Ash.Query.filter(appointment_id == ^appt.id) |> Ash.read!()
      assert length(payments) == 1
      assert hd(payments).amount_cents == expected_price
    end

    test "guest can book with SUV/Van (1.2x pricing)" do
      service = create_service()

      {:ok, guest} =
        Customer
        |> Ash.Changeset.for_create(:create_guest, %{
          email: "suv-#{:rand.uniform(100_000)}@example.com",
          name: "SUV Guest"
        })
        |> Ash.create()

      {:ok, vehicle} =
        Vehicle
        |> Ash.Changeset.for_create(:create, %{
          make: "Toyota",
          model: "Highlander",
          size: :suv_van
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, guest.id)
        |> Ash.create()

      {:ok, address} =
        Address
        |> Ash.Changeset.for_create(:create, %{
          street: "200 SUV St",
          city: "Austin",
          state: "TX",
          zip: "78702"
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, guest.id)
        |> Ash.create()

      tomorrow = Date.new!(2030, 8, 7)
      [slot | _] = Availability.available_slots(tomorrow, service.duration_minutes, [])

      {:ok, %{appointment: appt}} =
        Booking.create_booking(%{
          customer_id: guest.id,
          service_type_id: service.id,
          vehicle_id: vehicle.id,
          address_id: address.id,
          scheduled_at: slot.starts_at,
          subscription_id: nil
        })

      # SUV = $50 * 1.2 = $60
      assert appt.price_cents == 6000
    end

    test "guest can book with car (base pricing)" do
      service = create_service()

      {:ok, guest} =
        Customer
        |> Ash.Changeset.for_create(:create_guest, %{
          email: "car-#{:rand.uniform(100_000)}@example.com",
          name: "Car Guest"
        })
        |> Ash.create()

      {:ok, vehicle} =
        Vehicle
        |> Ash.Changeset.for_create(:create, %{make: "Honda", model: "Civic", size: :car})
        |> Ash.Changeset.force_change_attribute(:customer_id, guest.id)
        |> Ash.create()

      {:ok, address} =
        Address
        |> Ash.Changeset.for_create(:create, %{
          street: "300 Car St",
          city: "Austin",
          state: "TX",
          zip: "78703"
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, guest.id)
        |> Ash.create()

      tomorrow = Date.new!(2030, 8, 7)
      [slot | _] = Availability.available_slots(tomorrow, service.duration_minutes, [])

      {:ok, %{appointment: appt}} =
        Booking.create_booking(%{
          customer_id: guest.id,
          service_type_id: service.id,
          vehicle_id: vehicle.id,
          address_id: address.id,
          scheduled_at: slot.starts_at,
          subscription_id: nil
        })

      # Car = base price
      assert appt.price_cents == service.base_price_cents
      assert appt.price_cents == 5000
    end
  end
end
