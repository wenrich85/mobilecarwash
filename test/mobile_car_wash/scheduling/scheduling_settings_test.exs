defmodule MobileCarWash.Scheduling.SchedulingSettingsTest do
  @moduledoc """
  Singleton resource holding admin-tunable scheduling knobs. Starting with
  max_intra_block_drive_minutes (defaults to 20) — future knobs like
  travel_speed_mph and shop origin can join it without schema churn that
  touches unrelated code paths.
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Scheduling.SchedulingSettings

  describe "get/0" do
    test "returns the singleton row, creating it on first access with defaults" do
      settings = SchedulingSettings.get()

      assert settings.id
      assert settings.max_intra_block_drive_minutes == 20
    end

    test "returns the same row on repeated calls (singleton)" do
      a = SchedulingSettings.get()
      b = SchedulingSettings.get()

      assert a.id == b.id
    end
  end

  describe "update/1" do
    test "persists new values and subsequent get/0 reflects them" do
      {:ok, updated} =
        SchedulingSettings.update(%{max_intra_block_drive_minutes: 35})

      assert updated.max_intra_block_drive_minutes == 35
      assert SchedulingSettings.get().max_intra_block_drive_minutes == 35
    end

    test "rejects a non-positive threshold" do
      {:error, _} = SchedulingSettings.update(%{max_intra_block_drive_minutes: 0})
      {:error, _} = SchedulingSettings.update(%{max_intra_block_drive_minutes: -5})
    end
  end
end
