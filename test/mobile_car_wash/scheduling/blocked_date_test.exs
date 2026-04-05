defmodule MobileCarWash.Scheduling.BlockedDateTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Scheduling.BlockedDate

  describe "create" do
    test "creates a blocked date with reason" do
      {:ok, blocked} =
        BlockedDate
        |> Ash.Changeset.for_create(:create, %{date: ~D[2026-07-04], reason: "Independence Day"})
        |> Ash.create()

      assert blocked.date == ~D[2026-07-04]
      assert blocked.reason == "Independence Day"
    end

    test "creates without reason" do
      {:ok, blocked} =
        BlockedDate
        |> Ash.Changeset.for_create(:create, %{date: ~D[2026-12-25]})
        |> Ash.create()

      assert blocked.date == ~D[2026-12-25]
      assert blocked.reason == nil
    end
  end

  describe "for_range read" do
    test "returns blocked dates within a range" do
      for d <- [~D[2026-07-03], ~D[2026-07-04], ~D[2026-07-05], ~D[2026-08-01]] do
        BlockedDate |> Ash.Changeset.for_create(:create, %{date: d}) |> Ash.create!()
      end

      results =
        BlockedDate
        |> Ash.Query.for_read(:for_range, %{start_date: ~D[2026-07-01], end_date: ~D[2026-07-31]})
        |> Ash.read!()

      dates = Enum.map(results, & &1.date)
      assert ~D[2026-07-03] in dates
      assert ~D[2026-07-04] in dates
      assert ~D[2026-07-05] in dates
      refute ~D[2026-08-01] in dates
    end
  end

  describe "is_blocked? helper" do
    test "returns true for blocked dates" do
      BlockedDate |> Ash.Changeset.for_create(:create, %{date: ~D[2026-07-04]}) |> Ash.create!()

      assert BlockedDate.blocked?(~D[2026-07-04]) == true
      assert BlockedDate.blocked?(~D[2026-07-05]) == false
    end
  end
end
