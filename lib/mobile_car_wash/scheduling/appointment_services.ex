defmodule MobileCarWash.Scheduling.AppointmentServices do
  @moduledoc """
  Add-on services for appointments. `add/2` is the shared, charge-free
  attach core reused by the interactive one-off flow, the Stripe webhook,
  and the recurring scheduler. Charging lives in `request_add_services/2`
  and `complete_addon_checkout/1`.
  """

  alias MobileCarWash.Billing.Pricing
  alias MobileCarWash.Scheduling.{AddOn, AppointmentAddOn, RecurringScheduleAddOn}
  alias MobileCarWash.Fleet.Vehicle

  require Ash.Query

  @doc """
  Attaches the given add-ons to `appointment`, capturing size-scaled prices
  and bumping the appointment's `price_cents` by the delta. No payment.
  Returns `{:ok, appointment}` (unchanged if no active add-ons resolve).
  """
  def add(appointment, add_on_ids) do
    case load_active_add_ons(add_on_ids) do
      [] ->
        {:ok, appointment}

      add_ons ->
        vehicle = Ash.get!(Vehicle, appointment.vehicle_id, authorize?: false)

        Enum.each(add_ons, fn add_on ->
          AppointmentAddOn
          |> Ash.Changeset.for_create(:create, %{
            appointment_id: appointment.id,
            add_on_id: add_on.id,
            price_cents: Pricing.calculate(add_on.price_cents, vehicle.size)
          })
          |> Ash.create!()
        end)

        delta = Pricing.addons_total_cents(add_ons, vehicle.size)

        appointment
        |> Ash.Changeset.for_update(:update, %{price_cents: appointment.price_cents + delta})
        |> Ash.update()
    end
  end

  @doc false
  def load_active_add_ons(nil), do: []
  def load_active_add_ons([]), do: []

  def load_active_add_ons(ids) do
    AddOn
    |> Ash.Query.filter(id in ^ids and active == true)
    |> Ash.read!()
  end

  @doc """
  Replaces a recurring schedule's add-on set: deletes existing join rows,
  then creates one per active add-on id. Affects FUTURE occurrences only.
  """
  def replace_schedule_add_ons(schedule_id, add_on_ids) do
    RecurringScheduleAddOn
    |> Ash.Query.for_read(:for_schedule, %{recurring_schedule_id: schedule_id})
    |> Ash.read!()
    |> Enum.each(&Ash.destroy!/1)

    add_on_ids
    |> load_active_add_ons()
    |> Enum.each(fn add_on ->
      RecurringScheduleAddOn
      |> Ash.Changeset.for_create(:create, %{
        recurring_schedule_id: schedule_id,
        add_on_id: add_on.id
      })
      |> Ash.create!()
    end)

    :ok
  end

  @doc "Current add-on ids attached to a recurring schedule."
  def schedule_add_on_ids(schedule_id) do
    RecurringScheduleAddOn
    |> Ash.Query.for_read(:for_schedule, %{recurring_schedule_id: schedule_id})
    |> Ash.read!()
    |> Enum.map(& &1.add_on_id)
  end

  @doc "Loaded active AddOn records attached to a recurring schedule."
  def schedule_add_ons(schedule_id) do
    schedule_id
    |> schedule_add_on_ids()
    |> load_active_add_ons()
  end
end
