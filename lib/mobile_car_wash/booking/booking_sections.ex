defmodule MobileCarWash.Booking.BookingSections do
  @moduledoc """
  Pure section-status logic for the single-page booking flow.

  Given the accumulated selection context, reports each section's status
  (`:locked | :active | :complete`) and whether the order is payable. No
  Phoenix/Ash deps — drives the progressive-reveal UI and the Pay gate.
  """

  @sections [:service, :add_ons, :vehicle, :address, :schedule, :review]

  @type section :: :service | :add_ons | :vehicle | :address | :schedule | :review
  @type status :: :locked | :active | :complete
  @type context :: map()

  @doc "Sections in display order."
  @spec sections() :: [section()]
  def sections, do: @sections

  @doc "Status of a section given the current selections."
  @spec status(section(), context()) :: status()
  def status(:service, ctx),
    do: if(present?(ctx, :selected_service), do: :complete, else: :active)

  def status(:add_ons, ctx) do
    # Optional: never blocks. Active once a service is chosen; complete when
    # at least one add-on is selected (purely cosmetic — it stays passable).
    cond do
      not present?(ctx, :selected_service) -> :locked
      list_present?(ctx, :selected_add_ons) -> :complete
      true -> :active
    end
  end

  def status(:vehicle, ctx), do: gated(ctx, present?(ctx, :selected_service), :selected_vehicle)

  def status(:address, ctx),
    do: gated(ctx, complete?(:vehicle, ctx), :selected_address)

  def status(:schedule, ctx),
    do: gated(ctx, complete?(:address, ctx), :selected_slot)

  def status(:review, ctx),
    do: if(complete?(:schedule, ctx), do: :active, else: :locked)

  @doc "True when every required section is complete and a customer is present."
  @spec payable?(context()) :: boolean()
  def payable?(ctx) do
    complete?(:service, ctx) and complete?(:vehicle, ctx) and
      complete?(:address, ctx) and complete?(:schedule, ctx) and
      present?(ctx, :current_customer)
  end

  # A required section is locked until `unlocked?`, complete when its value is
  # present, else active.
  defp gated(ctx, unlocked?, key) do
    cond do
      not unlocked? -> :locked
      present?(ctx, key) -> :complete
      true -> :active
    end
  end

  defp complete?(section, ctx), do: status(section, ctx) == :complete

  defp present?(ctx, key), do: Map.get(ctx, key) != nil

  defp list_present?(ctx, key) do
    case Map.get(ctx, key) do
      [_ | _] -> true
      _ -> false
    end
  end
end
