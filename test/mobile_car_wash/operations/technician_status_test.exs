defmodule MobileCarWash.Operations.TechnicianStatusTest do
  @moduledoc """
  Covers the technician-level duty status — orthogonal to the
  per-appointment state machine. A tech is simultaneously either
  off_duty / available / on_break AND (if they have an active appointment)
  either en_route / on_site / washing via that appointment.

  Admin dispatch subscribes to the broadcast so the tech strip updates
  in real time when anyone taps "Break" or "Back on" from the dashboard.
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Operations.{Technician, TechnicianTracker}

  setup do
    {:ok, technician} =
      Technician
      |> Ash.Changeset.for_create(:create, %{
        name: "Miguel Status",
        phone: "+15125550100",
        active: true
      })
      |> Ash.create()

    %{technician: technician}
  end

  describe ":status attribute" do
    test "defaults to :off_duty on newly created technicians", %{technician: technician} do
      assert technician.status == :off_duty
    end

    test "accepts :available, :on_break, :off_duty via :set_status",
         %{technician: technician} do
      {:ok, available} =
        technician
        |> Ash.Changeset.for_update(:set_status, %{status: :available})
        |> Ash.update()

      assert available.status == :available

      {:ok, on_break} =
        available
        |> Ash.Changeset.for_update(:set_status, %{status: :on_break})
        |> Ash.update()

      assert on_break.status == :on_break

      {:ok, off_duty} =
        on_break
        |> Ash.Changeset.for_update(:set_status, %{status: :off_duty})
        |> Ash.update()

      assert off_duty.status == :off_duty
    end

    test "rejects values outside the enum", %{technician: technician} do
      {:error, _} =
        technician
        |> Ash.Changeset.for_update(:set_status, %{status: :on_vacation})
        |> Ash.update()
    end
  end

  describe "TechnicianTracker broadcasts" do
    test "set_status fires a broadcast on the per-technician topic",
         %{technician: technician} do
      TechnicianTracker.subscribe(technician.id)

      technician
      |> Ash.Changeset.for_update(:set_status, %{status: :available})
      |> Ash.update!()

      assert_receive {:technician_status, %{technician_id: id, status: :available}}, 500
      assert id == technician.id
    end

    test "set_status also fires on the global 'all techs' topic (for admin dispatch)",
         %{technician: technician} do
      TechnicianTracker.subscribe_all()

      technician
      |> Ash.Changeset.for_update(:set_status, %{status: :on_break})
      |> Ash.update!()

      assert_receive {:technician_status, %{technician_id: id, status: :on_break}}, 500
      assert id == technician.id
    end
  end
end
