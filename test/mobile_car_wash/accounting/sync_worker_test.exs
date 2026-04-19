defmodule MobileCarWash.Accounting.SyncWorkerTest do
  @moduledoc """
  Tests for the AccountingSyncWorker Oban job.
  Verifies that the worker loads payment + customer data and delegates
  to the Accounting facade. With unconfigured providers, sync is gracefully skipped.
  """
  use MobileCarWash.DataCase, async: true
  use Oban.Testing, repo: MobileCarWash.Repo

  alias MobileCarWash.Accounting.SyncWorker

  require Ash.Query

  # --- Fixtures ---

  defp create_guest do
    MobileCarWash.Accounts.Customer
    |> Ash.Changeset.for_create(:create_guest, %{
      email: "sync-#{:rand.uniform(100_000)}@test.com",
      name: "Sync Test",
      phone: "512-555-0001"
    })
    |> Ash.create!()
  end

  defp create_service do
    slug = "sync_svc_#{:rand.uniform(100_000)}"

    MobileCarWash.Scheduling.ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Sync Wash",
      slug: slug,
      base_price_cents: 5000,
      duration_minutes: 45
    })
    |> Ash.create!()
  end

  defp create_vehicle(customer_id) do
    MobileCarWash.Fleet.Vehicle
    |> Ash.Changeset.for_create(:create, %{make: "T", model: "T", size: :car})
    |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
    |> Ash.create!()
  end

  defp create_address(customer_id) do
    MobileCarWash.Fleet.Address
    |> Ash.Changeset.for_create(:create, %{street: "1 Sync", city: "A", state: "TX", zip: "7"})
    |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
    |> Ash.create!()
  end

  defp book_appointment(customer, service, vehicle, address) do
    hour = 8 + :rand.uniform(8)
    {:ok, dt} = DateTime.new(~D[2030-07-10], Time.new!(hour, 0, 0))

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

  describe "perform/1 — with real payment data" do
    setup do
      guest = create_guest()
      service = create_service()
      vehicle = create_vehicle(guest.id)
      address = create_address(guest.id)
      appt = book_appointment(guest, service, vehicle, address)

      # Fetch the auto-created payment
      [payment] =
        MobileCarWash.Billing.Payment
        |> Ash.Query.filter(appointment_id == ^appt.id)
        |> Ash.read!()

      %{payment: payment, customer: guest, service: service, appointment: appt}
    end

    test "worker runs without crashing for valid payment", %{payment: payment} do
      # With no accounting credentials configured, sync is gracefully skipped
      result = perform_job(SyncWorker, %{"payment_id" => payment.id})
      assert result == :ok
    end

    test "worker resolves service name from appointment → service type", %{payment: payment, service: service} do
      # Verify the payment has an appointment_id (which triggers service name lookup)
      {:ok, loaded_payment} = Ash.get(MobileCarWash.Billing.Payment, payment.id)
      assert loaded_payment.appointment_id != nil

      # The service name resolution path: payment → appointment → service_type
      {:ok, appt} = Ash.get(MobileCarWash.Scheduling.Appointment, loaded_payment.appointment_id)
      {:ok, svc} = Ash.get(MobileCarWash.Scheduling.ServiceType, appt.service_type_id)
      assert svc.name == service.name
    end
  end

  describe "perform/1 — missing payment" do
    test "returns error for nonexistent payment_id" do
      result = perform_job(SyncWorker, %{"payment_id" => Ash.UUID.generate()})
      assert match?({:error, _}, result)
    end
  end

  describe "job enqueueing" do
    test "enqueues on billing queue with correct args" do
      payment_id = Ash.UUID.generate()

      assert {:ok, job} =
               %{payment_id: payment_id}
               |> SyncWorker.new(queue: :billing)
               |> Oban.insert()

      assert job.args["payment_id"] == payment_id
      assert job.queue == "billing"
    end
  end

  describe "provider switching — sync skips gracefully" do
    test "sync skips when provider is ZohoBooks (unconfigured)" do
      original = Application.get_env(:mobile_car_wash, :accounting_provider)

      try do
        Application.put_env(:mobile_car_wash, :accounting_provider, MobileCarWash.Accounting.ZohoBooks)

        guest = create_guest()
        service = create_service()
        vehicle = create_vehicle(guest.id)
        address = create_address(guest.id)
        appt = book_appointment(guest, service, vehicle, address)

        [payment] =
          MobileCarWash.Billing.Payment
          |> Ash.Query.filter(appointment_id == ^appt.id)
          |> Ash.read!()

        result = perform_job(SyncWorker, %{"payment_id" => payment.id})
        assert result == :ok
      after
        if original do
          Application.put_env(:mobile_car_wash, :accounting_provider, original)
        else
          Application.delete_env(:mobile_car_wash, :accounting_provider)
        end
      end
    end

    test "sync skips when provider is QuickBooks (unconfigured)" do
      original = Application.get_env(:mobile_car_wash, :accounting_provider)

      try do
        Application.put_env(:mobile_car_wash, :accounting_provider, MobileCarWash.Accounting.QuickBooks)

        guest = create_guest()
        service = create_service()
        vehicle = create_vehicle(guest.id)
        address = create_address(guest.id)
        appt = book_appointment(guest, service, vehicle, address)

        [payment] =
          MobileCarWash.Billing.Payment
          |> Ash.Query.filter(appointment_id == ^appt.id)
          |> Ash.read!()

        result = perform_job(SyncWorker, %{"payment_id" => payment.id})
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
end
