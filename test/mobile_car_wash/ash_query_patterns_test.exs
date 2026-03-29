defmodule MobileCarWash.AshQueryPatternsTest do
  @moduledoc """
  Tests every Ash query pattern used in the application to ensure
  we're using the correct Ash 3.x API (Ash.Query.filter, not
  Ash.read! with action:/arguments:/filter: options).

  This test file exists because we repeatedly hit the same bug:
  Ash.read!(Resource, action: :name, arguments: %{...}) is invalid
  in Ash 3.x. The correct pattern is:
    Resource |> Ash.Query.filter(field == ^value) |> Ash.read!()
  """
  use MobileCarWash.DataCase, async: true

  require Ash.Query

  # --- Setup helpers ---

  defp create_customer do
    MobileCarWash.Accounts.Customer
    |> Ash.Changeset.for_create(:create_guest, %{
      email: "query-test-#{:rand.uniform(100_000)}@test.com",
      name: "Query Test",
      phone: "555"
    })
    |> Ash.create!()
  end

  defp create_vehicle(customer_id) do
    MobileCarWash.Fleet.Vehicle
    |> Ash.Changeset.for_create(:create, %{make: "Test", model: "Car", size: :car})
    |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
    |> Ash.create!()
  end

  defp create_address(customer_id) do
    MobileCarWash.Fleet.Address
    |> Ash.Changeset.for_create(:create, %{street: "1 Test", city: "A", state: "TX", zip: "7"})
    |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
    |> Ash.create!()
  end

  # === Vehicle queries (used in booking flow load_step_data) ===

  describe "Vehicle queries" do
    test "filter by customer_id" do
      customer = create_customer()
      vehicle = create_vehicle(customer.id)

      results =
        MobileCarWash.Fleet.Vehicle
        |> Ash.Query.filter(customer_id == ^customer.id)
        |> Ash.read!()

      assert length(results) == 1
      assert hd(results).id == vehicle.id
    end

    test "returns empty list for unknown customer" do
      results =
        MobileCarWash.Fleet.Vehicle
        |> Ash.Query.filter(customer_id == ^Ash.UUID.generate())
        |> Ash.read!()

      assert results == []
    end
  end

  # === Address queries (used in booking flow load_step_data) ===

  describe "Address queries" do
    test "filter by customer_id" do
      customer = create_customer()
      address = create_address(customer.id)

      results =
        MobileCarWash.Fleet.Address
        |> Ash.Query.filter(customer_id == ^customer.id)
        |> Ash.read!()

      assert length(results) == 1
      assert hd(results).id == address.id
    end
  end

  # === Appointment queries (used in dispatch, availability, booking) ===

  describe "Appointment queries" do
    test "filter by status" do
      results =
        MobileCarWash.Scheduling.Appointment
        |> Ash.Query.filter(status == :in_progress)
        |> Ash.read!()

      # Just verify it doesn't crash — may be empty
      assert is_list(results)
    end

    test "filter by date range" do
      {:ok, start_dt} = DateTime.new(~D[2030-01-01], ~T[00:00:00])
      {:ok, end_dt} = DateTime.new(~D[2030-01-02], ~T[00:00:00])

      results =
        MobileCarWash.Scheduling.Appointment
        |> Ash.Query.filter(scheduled_at >= ^start_dt and scheduled_at < ^end_dt)
        |> Ash.read!()

      assert is_list(results)
    end

    test "filter by technician_id" do
      results =
        MobileCarWash.Scheduling.Appointment
        |> Ash.Query.filter(technician_id == ^Ash.UUID.generate())
        |> Ash.read!()

      assert is_list(results)
    end

    test "filter unassigned (technician_id is nil)" do
      results =
        MobileCarWash.Scheduling.Appointment
        |> Ash.Query.filter(is_nil(technician_id))
        |> Ash.read!()

      assert is_list(results)
    end

    test "combined status + date filter" do
      {:ok, start_dt} = DateTime.new(~D[2030-06-01], ~T[00:00:00])
      {:ok, end_dt} = DateTime.new(~D[2030-06-02], ~T[00:00:00])

      results =
        MobileCarWash.Scheduling.Appointment
        |> Ash.Query.filter(
          status == :pending and
            scheduled_at >= ^start_dt and
            scheduled_at < ^end_dt
        )
        |> Ash.read!()

      assert is_list(results)
    end
  end

  # === ServiceType queries ===

  describe "ServiceType queries" do
    test "filter by slug" do
      results =
        MobileCarWash.Scheduling.ServiceType
        |> Ash.Query.filter(slug == "basic_wash")
        |> Ash.read!()

      # May or may not exist in test DB
      assert is_list(results)
    end

    test "filter active" do
      results =
        MobileCarWash.Scheduling.ServiceType
        |> Ash.Query.filter(active == true)
        |> Ash.read!()

      assert is_list(results)
    end
  end

  # === Customer queries ===

  describe "Customer queries" do
    test "filter by email" do
      customer = create_customer()

      results =
        MobileCarWash.Accounts.Customer
        |> Ash.Query.filter(email == ^to_string(customer.email))
        |> Ash.read!()

      assert length(results) == 1
    end

    test "filter by role" do
      results =
        MobileCarWash.Accounts.Customer
        |> Ash.Query.filter(role == :technician)
        |> Ash.read!()

      assert is_list(results)
    end
  end

  # === Photo queries ===

  describe "Photo queries" do
    test "filter by appointment_id" do
      results =
        MobileCarWash.Operations.Photo
        |> Ash.Query.filter(appointment_id == ^Ash.UUID.generate())
        |> Ash.read!()

      assert results == []
    end

    test "filter by appointment_id and photo_type" do
      results =
        MobileCarWash.Operations.Photo
        |> Ash.Query.filter(
          appointment_id == ^Ash.UUID.generate() and
            photo_type == :problem_area
        )
        |> Ash.read!()

      assert results == []
    end
  end

  # === Event queries ===

  describe "Event queries" do
    test "filter by event_name and date range" do
      {:ok, start_dt} = DateTime.new(~D[2030-01-01], ~T[00:00:00])
      {:ok, end_dt} = DateTime.new(~D[2030-01-02], ~T[00:00:00])

      results =
        MobileCarWash.Analytics.Event
        |> Ash.Query.filter(
          event_name == "page.viewed" and
            inserted_at >= ^start_dt and
            inserted_at < ^end_dt
        )
        |> Ash.read!()

      assert is_list(results)
    end
  end

  # === ChecklistItem queries ===

  describe "ChecklistItem queries" do
    test "filter by checklist_id" do
      results =
        MobileCarWash.Operations.ChecklistItem
        |> Ash.Query.filter(checklist_id == ^Ash.UUID.generate())
        |> Ash.read!()

      assert results == []
    end
  end

  # === AppointmentChecklist queries ===

  describe "AppointmentChecklist queries" do
    test "filter by appointment_id" do
      results =
        MobileCarWash.Operations.AppointmentChecklist
        |> Ash.Query.filter(appointment_id == ^Ash.UUID.generate())
        |> Ash.read!()

      assert results == []
    end
  end
end
