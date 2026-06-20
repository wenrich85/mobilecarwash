defmodule MobileCarWash.Booking.BookingSectionsTest do
  use ExUnit.Case, async: true

  alias MobileCarWash.Booking.BookingSections

  defp ctx(overrides),
    do:
      Map.merge(
        %{
          selected_service: nil,
          selected_add_ons: [],
          selected_vehicle: nil,
          selected_address: nil,
          selected_slot: nil,
          current_customer: nil
        },
        overrides
      )

  test "section order is service → add_ons → vehicle → address → schedule → review" do
    assert BookingSections.sections() ==
             [:service, :add_ons, :vehicle, :address, :schedule, :review]
  end

  test "service is active and everything after it is locked when nothing is chosen" do
    c = ctx(%{})
    assert BookingSections.status(:service, c) == :active
    assert BookingSections.status(:add_ons, c) == :locked
    assert BookingSections.status(:vehicle, c) == :locked
    assert BookingSections.status(:review, c) == :locked
  end

  test "choosing a service completes it and unlocks add_ons + vehicle" do
    c = ctx(%{selected_service: %{id: "s"}})
    assert BookingSections.status(:service, c) == :complete
    # add_ons is optional → active (never blocks) once service is chosen
    assert BookingSections.status(:add_ons, c) == :active
    assert BookingSections.status(:vehicle, c) == :active
    assert BookingSections.status(:address, c) == :locked
  end

  test "a chosen vehicle completes vehicle and unlocks address" do
    c = ctx(%{selected_service: %{id: "s"}, selected_vehicle: %{id: "v"}})
    assert BookingSections.status(:vehicle, c) == :complete
    assert BookingSections.status(:address, c) == :active
    assert BookingSections.status(:schedule, c) == :locked
  end

  test "address then schedule unlock in order; review unlocks after a slot" do
    c =
      ctx(%{
        selected_service: %{id: "s"},
        selected_vehicle: %{id: "v"},
        selected_address: %{id: "a"}
      })

    assert BookingSections.status(:address, c) == :complete
    assert BookingSections.status(:schedule, c) == :active
    assert BookingSections.status(:review, c) == :locked

    c2 = Map.put(c, :selected_slot, %{id: "slot"})
    assert BookingSections.status(:schedule, c2) == :complete
    assert BookingSections.status(:review, c2) == :active
  end

  test "payable? only when all required sections complete AND a customer is present" do
    full =
      ctx(%{
        selected_service: %{id: "s"},
        selected_vehicle: %{id: "v"},
        selected_address: %{id: "a"},
        selected_slot: %{id: "slot"}
      })

    # No customer yet (guest hasn't entered contact) → not payable
    refute BookingSections.payable?(full)
    assert BookingSections.payable?(Map.put(full, :current_customer, %{id: "c"}))
    # Missing a slot → not payable even with a customer
    refute BookingSections.payable?(%{full | selected_slot: nil, current_customer: %{id: "c"}})
  end

  test "payable? for a guest requires a non-blank email and all required sections" do
    complete = ctx(%{
      selected_service: %{id: "s"}, selected_vehicle: %{id: "v"},
      selected_address: %{id: "a"}, selected_slot: %{id: "slot"}
    })

    # Guest with a real email + all sections complete → payable
    assert BookingSections.payable?(Map.put(complete, :guest_form, %{"email" => "g@example.com"}))
    # Guest with a blank/whitespace email → not payable
    refute BookingSections.payable?(Map.put(complete, :guest_form, %{"email" => "   "}))
    # No customer and no guest_form at all → not payable
    refute BookingSections.payable?(complete)
    # Guest email present but a required section missing (no slot) → not payable
    incomplete = %{complete | selected_slot: nil}
    refute BookingSections.payable?(Map.put(incomplete, :guest_form, %{"email" => "g@example.com"}))
  end
end
