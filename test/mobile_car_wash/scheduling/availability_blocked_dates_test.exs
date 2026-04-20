defmodule MobileCarWash.Scheduling.AvailabilityBlockedDatesTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Scheduling.{Availability, BlockedDate}

  test "available_slots returns empty for a blocked date" do
    BlockedDate
    |> Ash.Changeset.for_create(:create, %{date: ~D[2030-03-04], reason: "Holiday"})
    |> Ash.create!()

    slots = Availability.available_slots(~D[2030-03-04], 45, [])
    assert slots == []
  end

  test "available_slots returns slots for non-blocked dates" do
    # Block a different date
    BlockedDate |> Ash.Changeset.for_create(:create, %{date: ~D[2030-03-05]}) |> Ash.create!()

    # This date is not blocked
    slots = Availability.available_slots(~D[2030-03-04], 45, [])
    assert length(slots) > 0
  end

  test "slot_available? returns false for a blocked date" do
    BlockedDate |> Ash.Changeset.for_create(:create, %{date: ~D[2030-03-04]}) |> Ash.create!()

    {:ok, datetime} = DateTime.new(~D[2030-03-04], ~T[10:00:00])
    refute Availability.slot_available?(datetime, 45, [])
  end
end
