defmodule MobileCarWash.Scheduling.AvailabilityTest do
  use ExUnit.Case, async: true

  alias MobileCarWash.Scheduling.Availability

  # Monday March 30, 2026
  @test_date ~D[2026-03-30]

  defp make_appointment(date, hour, minute \\ 0, duration \\ 45) do
    {:ok, scheduled_at} = DateTime.new(date, Time.new!(hour, minute, 0))
    %{scheduled_at: scheduled_at, duration_minutes: duration}
  end

  describe "available_slots/4" do
    test "returns slots within business hours for an empty day" do
      slots = Availability.available_slots(@test_date, 45, [])

      assert length(slots) > 0

      for slot <- slots do
        assert slot.starts_at.hour >= 8
        assert Time.compare(DateTime.to_time(slot.ends_at), ~T[18:00:00]) in [:lt, :eq]
      end
    end

    test "calculates correct number of 45-min slots with 15-min buffer" do
      # 8am-6pm = 600 min, slot = 45+15 = 60 min each
      # 8:00, 9:00, 10:00, 11:00, 12:00, 13:00, 14:00, 15:00, 16:00, 17:00
      # Last slot 17:00 ends at 17:45 ≤ 18:00 ✓
      slots = Availability.available_slots(@test_date, 45, [])
      assert length(slots) == 10
    end

    test "calculates correct number of 120-min slots with 15-min buffer" do
      # slot = 120+15 = 135 min each
      # 8:00→10:00, 10:15→12:15, 12:30→14:30, 14:45→16:45
      # Next 17:00→19:00 exceeds 18:00
      slots = Availability.available_slots(@test_date, 120, [])
      assert length(slots) == 4
    end

    test "excludes slots that overlap with existing appointments" do
      existing = [make_appointment(@test_date, 14)]

      slots = Availability.available_slots(@test_date, 45, existing)
      start_hours = Enum.map(slots, & &1.starts_at.hour)
      refute 14 in start_hours
    end

    test "respects buffer time around existing appointments" do
      existing = [make_appointment(@test_date, 10, 0, 45)]

      slots = Availability.available_slots(@test_date, 45, existing)

      for slot <- slots do
        # No slot should overlap with the 10:00-10:45 appointment + 15 min buffer
        refute slot.starts_at.hour == 10
      end
    end

    test "returns empty list for fully booked day" do
      existing = for hour <- 8..17, do: make_appointment(@test_date, hour)

      slots = Availability.available_slots(@test_date, 45, existing)
      assert slots == []
    end

    test "returns empty list for Sundays" do
      sunday = ~D[2026-04-05]
      slots = Availability.available_slots(sunday, 45, [])
      assert slots == []
    end

    test "returns slots for Saturdays" do
      saturday = ~D[2026-04-04]
      slots = Availability.available_slots(saturday, 45, [])
      assert length(slots) > 0
    end

    test "rejects dates in the past" do
      past_date = ~D[2020-01-01]
      slots = Availability.available_slots(past_date, 45, [])
      assert slots == []
    end
  end

  describe "slot_available?/3" do
    test "returns true for an open slot" do
      {:ok, datetime} = DateTime.new(~D[2026-03-30], ~T[10:00:00])
      assert Availability.slot_available?(datetime, 45, [])
    end

    test "returns false for a conflicting slot" do
      {:ok, datetime} = DateTime.new(~D[2026-03-30], ~T[10:00:00])
      existing = [make_appointment(~D[2026-03-30], 10)]

      refute Availability.slot_available?(datetime, 45, existing)
    end

    test "returns false for a slot in the past" do
      {:ok, past} = DateTime.new(~D[2020-01-01], ~T[10:00:00])
      refute Availability.slot_available?(past, 45, [])
    end

    test "returns false for Sunday" do
      {:ok, sunday} = DateTime.new(~D[2026-04-05], ~T[10:00:00])
      refute Availability.slot_available?(sunday, 45, [])
    end

    test "returns false outside business hours" do
      {:ok, early} = DateTime.new(~D[2026-03-30], ~T[07:00:00])
      {:ok, late} = DateTime.new(~D[2026-03-30], ~T[17:30:00])

      refute Availability.slot_available?(early, 45, [])
      refute Availability.slot_available?(late, 120, [])
    end
  end
end
