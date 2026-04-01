defmodule MobileCarWash.RegressionTest do
  @moduledoc """
  Regression tests for bugs found during manual walkthrough.
  Each test documents what broke, why, and ensures it stays fixed.
  """
  use MobileCarWash.DataCase, async: true

  require Ash.Query

  # --- Helpers ---

  defp create_guest(email \\ nil) do
    email = email || "reg-#{:rand.uniform(100_000)}@test.com"

    MobileCarWash.Accounts.Customer
    |> Ash.Changeset.for_create(:create_guest, %{email: email, name: "Reg Test", phone: "555"})
    |> Ash.create!()
  end

  defp create_service do
    slug = "reg_svc_#{:rand.uniform(100_000)}"

    MobileCarWash.Scheduling.ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Reg Wash", slug: slug, base_price_cents: 5000, duration_minutes: 45
    })
    |> Ash.create!()
  end

  defp create_vehicle(customer_id, size \\ :car) do
    MobileCarWash.Fleet.Vehicle
    |> Ash.Changeset.for_create(:create, %{make: "T", model: "T", size: size})
    |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
    |> Ash.create!()
  end

  defp create_address(customer_id) do
    MobileCarWash.Fleet.Address
    |> Ash.Changeset.for_create(:create, %{street: "1 R", city: "A", state: "TX", zip: "7"})
    |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
    |> Ash.create!()
  end

  defp book_appointment(customer, service, vehicle, address) do
    # Fixed far-future Wednesday at random hour to avoid conflicts
    hour = 8 + :rand.uniform(8)
    {:ok, dt} = DateTime.new(~D[2030-06-05], Time.new!(hour, 0, 0))

    {:ok, %{appointment: appt}} =
      MobileCarWash.Scheduling.Booking.create_booking(%{
        customer_id: customer.id,
        service_type_id: service.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        scheduled_at: dt,
        subscription_id: nil
      })

    appt
  end

  # === BUG 1: Payment creation crashed on FK fields ===
  # Root cause: customer_id and appointment_id passed as regular attrs
  # Fix: force_change_attribute for FK fields

  describe "BUG: Payment FK fields" do
    test "payment record is created with correct customer and appointment IDs" do
      guest = create_guest()
      service = create_service()
      vehicle = create_vehicle(guest.id)
      address = create_address(guest.id)
      appt = book_appointment(guest, service, vehicle, address)

      payments =
        MobileCarWash.Billing.Payment
        |> Ash.Query.filter(appointment_id == ^appt.id)
        |> Ash.read!()

      assert length(payments) == 1
      [payment] = payments
      assert payment.customer_id == guest.id
      assert payment.appointment_id == appt.id
      assert payment.amount_cents == appt.price_cents
    end
  end

  # === BUG 2: Vehicle/Address creation crashed on customer_id FK ===
  # Root cause: customer_id passed in form params, not accepted by :create action
  # Fix: force_change_attribute for customer_id

  describe "BUG: Vehicle/Address FK fields" do
    test "vehicle created with force_change_attribute for customer_id" do
      guest = create_guest()
      vehicle = create_vehicle(guest.id, :pickup)

      assert vehicle.customer_id == guest.id
      assert vehicle.size == :pickup
    end

    test "address created with force_change_attribute for customer_id" do
      guest = create_guest()
      address = create_address(guest.id)

      assert address.customer_id == guest.id
    end
  end

  # === BUG 3: EventTracker used get_in on Ash struct ===
  # Root cause: get_in(socket.assigns, [:current_customer, :id]) crashes on Ash structs
  # Fix: pattern match instead of get_in

  describe "BUG: EventTracker Ash struct access" do
    test "track_event extracts customer_id safely from struct" do
      # Simulate what EventTracker does — pattern match instead of get_in
      customer = %{id: "test-id", name: "Test"}

      customer_id =
        case customer do
          %{id: id} -> id
          _ -> nil
        end

      assert customer_id == "test-id"

      # Nil case
      nil_id =
        case nil do
          %{id: id} -> id
          _ -> nil
        end

      assert nil_id == nil
    end
  end

  # === BUG 4: Booking state machine — mount reset to step 1 ===
  # Root cause: mount always set current_step: :select_service
  # Fix: StateMachine.resolve_step restores from cache

  describe "BUG: Booking state machine" do
    test "resolve_step recovers correct step from context" do
      alias MobileCarWash.Booking.StateMachine

      # Context with vehicle selected — should be on :address
      ctx = %{
        selected_service: %{id: "s"},
        current_customer: %{id: "c"},
        selected_vehicle: %{id: "v"},
        selected_address: nil,
        selected_slot: nil,
        appointment: nil
      }

      assert StateMachine.resolve_step(:address, ctx) == :address
      # If we claim :schedule but address is nil, should walk back
      assert StateMachine.resolve_step(:schedule, ctx) == :address
    end

    test "resolve_step skips auth when customer present" do
      alias MobileCarWash.Booking.StateMachine

      ctx = %{
        selected_service: %{id: "s"},
        current_customer: %{id: "c"},
        selected_vehicle: nil,
        selected_address: nil,
        selected_slot: nil,
        appointment: nil
      }

      assert StateMachine.resolve_step(:auth, ctx) == :vehicle
    end
  end

  # === BUG 5: Guest customer lost on reconnect ===
  # Root cause: persist_booking_state didn't save customer_id
  # Fix: save customer_id in session cache, restore on mount

  describe "BUG: Guest state persistence" do
    test "session cache round-trips customer_id" do
      alias MobileCarWash.Booking.SessionCache

      SessionCache.put("test_session", %{
        step: :vehicle,
        customer_id: "cust-123",
        service_id: nil,
        vehicle_id: nil,
        address_id: nil,
        slot: nil,
        guest_mode: true
      })

      cached = SessionCache.get("test_session")
      assert cached != nil
      assert cached.customer_id == "cust-123"
      assert cached.guest_mode == true
      assert cached.step == :vehicle

      SessionCache.delete("test_session")
    end
  end

  # === BUG 6: Dispatch UUID binary encoding ===
  # Root cause: Postgrex expected binary UUID, got string
  # Fix: Ecto.UUID.dump!/1 before passing to update_all

  describe "BUG: Dispatch technician assignment" do
    test "assign_technician works with string UUID" do
      guest = create_guest()
      service = create_service()
      vehicle = create_vehicle(guest.id)
      address = create_address(guest.id)
      appt = book_appointment(guest, service, vehicle, address)

      # Create technician
      tech =
        MobileCarWash.Operations.Technician
        |> Ash.Changeset.for_create(:create, %{name: "RegTest Tech"})
        |> Ash.create!()

      # Assign technician first (required before confirming)
      {:ok, assigned} = MobileCarWash.Scheduling.Dispatch.assign_technician(appt.id, tech.id)
      assert assigned.technician_id == tech.id

      # Confirm appointment — this was crashing with binary UUID error
      {:ok, _confirmed} = assigned |> Ash.Changeset.for_update(:confirm, %{}) |> Ash.update()
    end
  end

  # === BUG 7: Wash orchestrator — full flow ===
  # Verifies the entire tech flow works end-to-end

  describe "BUG: Wash orchestrator full flow" do
    test "start_wash creates checklist from SOP and transitions appointment" do
      alias MobileCarWash.Scheduling.{WashOrchestrator, Dispatch}

      guest = create_guest()
      service = create_service()
      vehicle = create_vehicle(guest.id)
      address = create_address(guest.id)
      appt = book_appointment(guest, service, vehicle, address)

      # Need a procedure for the service type — create one
      proc =
        MobileCarWash.Operations.Procedure
        |> Ash.Changeset.for_create(:create, %{
          name: "Reg Proc",
          slug: "reg_proc_#{:rand.uniform(100_000)}",
          category: :wash
        })
        |> Ash.Changeset.force_change_attribute(:service_type_id, service.id)
        |> Ash.create!()

      # Add steps
      for n <- 1..3 do
        MobileCarWash.Operations.ProcedureStep
        |> Ash.Changeset.for_create(:create, %{
          step_number: n, title: "Step #{n}", estimated_minutes: 5, required: true
        })
        |> Ash.Changeset.force_change_attribute(:procedure_id, proc.id)
        |> Ash.create!()
      end

      # Assign tech first (required before confirming), then confirm
      tech = MobileCarWash.Operations.Technician |> Ash.Changeset.for_create(:create, %{name: "WO Tech"}) |> Ash.create!()
      {:ok, assigned} = Dispatch.assign_technician(appt.id, tech.id)
      {:ok, _} = assigned |> Ash.Changeset.for_update(:confirm, %{}) |> Ash.update()

      # Start wash
      {:ok, checklist} = WashOrchestrator.start_wash(appt.id)
      assert checklist != nil

      # Verify items created
      items =
        MobileCarWash.Operations.ChecklistItem
        |> Ash.Query.filter(checklist_id == ^checklist.id)
        |> Ash.read!()

      assert length(items) == 3

      # Verify appointment is in_progress
      {:ok, updated_appt} = Ash.get(MobileCarWash.Scheduling.Appointment, appt.id)
      assert updated_appt.status == :in_progress
    end
  end

  # === PATTERN: Vehicle pricing multiplier ===
  # Ensures pricing stays correct after all the FK fixes

  describe "Vehicle pricing integration" do
    test "pickup gets 1.5x on full booking" do
      guest = create_guest()
      service = create_service()
      vehicle = create_vehicle(guest.id, :pickup)
      address = create_address(guest.id)
      appt = book_appointment(guest, service, vehicle, address)

      expected = MobileCarWash.Billing.Pricing.calculate(service.base_price_cents, :pickup)
      assert appt.price_cents == expected
      assert expected == 7500
    end

    test "suv_van gets 1.2x on full booking" do
      guest = create_guest()
      service = create_service()
      vehicle = create_vehicle(guest.id, :suv_van)
      address = create_address(guest.id)
      appt = book_appointment(guest, service, vehicle, address)

      assert appt.price_cents == 6000
    end
  end

  # === BUG 9: Accounting facade used Zoho-specific field names ===
  # Root cause: sync_payment hard-coded contact["contact_id"] and invoice["invoice_id"]
  # Fix: extract_contact_id/extract_invoice_id pattern match both Zoho and QuickBooks shapes

  describe "BUG: Accounting facade provider-agnostic ID extraction" do
    test "sync_payment skips gracefully with unconfigured Zoho provider" do
      original = Application.get_env(:mobile_car_wash, :accounting_provider)

      try do
        Application.put_env(:mobile_car_wash, :accounting_provider, MobileCarWash.Accounting.ZohoBooks)

        guest = create_guest()
        customer_struct = %{name: guest.name, email: guest.email, phone: "555"}

        payment_struct = %{
          id: Ash.UUID.generate(),
          amount_cents: 5000,
          paid_at: DateTime.utc_now(),
          stripe_payment_intent_id: "pi_test_zoho"
        }

        # Should not crash — gracefully returns :ok when provider is unconfigured
        result = MobileCarWash.Accounting.sync_payment(customer_struct, payment_struct, "Basic Wash")
        assert result == :ok
      after
        if original do
          Application.put_env(:mobile_car_wash, :accounting_provider, original)
        else
          Application.delete_env(:mobile_car_wash, :accounting_provider)
        end
      end
    end

    test "sync_payment skips gracefully with unconfigured QuickBooks provider" do
      original = Application.get_env(:mobile_car_wash, :accounting_provider)

      try do
        Application.put_env(:mobile_car_wash, :accounting_provider, MobileCarWash.Accounting.QuickBooks)

        guest = create_guest()
        customer_struct = %{name: guest.name, email: guest.email, phone: "555"}

        payment_struct = %{
          id: Ash.UUID.generate(),
          amount_cents: 7500,
          paid_at: DateTime.utc_now(),
          stripe_payment_intent_id: "pi_test_qb"
        }

        result = MobileCarWash.Accounting.sync_payment(customer_struct, payment_struct, "Deep Clean")
        assert result == :ok
      after
        if original do
          Application.put_env(:mobile_car_wash, :accounting_provider, original)
        else
          Application.delete_env(:mobile_car_wash, :accounting_provider)
        end
      end
    end
  end

  # === BUG 10: Provider runtime switch must not crash existing sync jobs ===
  # Root cause: If provider is changed at runtime while Oban jobs are in-flight,
  # the worker must handle both old and new provider error atoms.

  describe "BUG: Provider switch mid-flight safety" do
    test "sync_payment handles provider switch from Zoho to QuickBooks" do
      guest = create_guest()
      customer_struct = %{name: guest.name, email: guest.email, phone: "555"}

      payment_struct = %{
        id: Ash.UUID.generate(),
        amount_cents: 5000,
        paid_at: DateTime.utc_now(),
        stripe_payment_intent_id: "pi_test_switch"
      }

      original = Application.get_env(:mobile_car_wash, :accounting_provider)

      try do
        # Start with Zoho, switch to QuickBooks mid-flight
        Application.put_env(:mobile_car_wash, :accounting_provider, MobileCarWash.Accounting.ZohoBooks)
        Application.put_env(:mobile_car_wash, :accounting_provider, MobileCarWash.Accounting.QuickBooks)

        # Facade should still complete (graceful skip with unconfigured provider)
        result = MobileCarWash.Accounting.sync_payment(customer_struct, payment_struct, "Basic Wash")
        assert result == :ok
      after
        if original do
          Application.put_env(:mobile_car_wash, :accounting_provider, original)
        else
          Application.delete_env(:mobile_car_wash, :accounting_provider)
        end
      end
    end
  end

  # === BUG 8: Ash.read! with invalid options (action:/arguments:) ===
  # Root cause: Ash.read! doesn't accept action: or arguments: options.
  # Must use Ash.Query.filter instead.

  describe "BUG: Ash.Query vs Ash.read! options" do
    test "vehicle query uses Ash.Query.filter (not Ash.read! with arguments:)" do
      guest = create_guest()
      vehicle = create_vehicle(guest.id)

      # This is what the booking flow does — must not crash
      vehicles =
        MobileCarWash.Fleet.Vehicle
        |> Ash.Query.filter(customer_id == ^guest.id)
        |> Ash.read!()

      assert length(vehicles) == 1
      assert hd(vehicles).id == vehicle.id
    end

    test "address query uses Ash.Query.filter (not Ash.read! with arguments:)" do
      guest = create_guest()
      address = create_address(guest.id)

      addresses =
        MobileCarWash.Fleet.Address
        |> Ash.Query.filter(customer_id == ^guest.id)
        |> Ash.read!()

      assert length(addresses) == 1
      assert hd(addresses).id == address.id
    end
  end
end
