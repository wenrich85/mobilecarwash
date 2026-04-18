defmodule MobileCarWashWeb.Admin.TechniciansLiveTest do
  @moduledoc """
  Tests for the admin Technicians index at /admin/technicians.
  """
  use MobileCarWashWeb.ConnCase, async: true

  describe "auth guard" do
    test "non-authenticated user is redirected to sign-in", %{conn: conn} do
      conn = get(conn, ~p"/admin/technicians")
      assert redirected_to(conn) == "/sign-in"
    end
  end

  describe "technician resource CRUD" do
    test "creating a technician with a zone persists correctly" do
      {:ok, tech} =
        MobileCarWash.Operations.Technician
        |> Ash.Changeset.for_create(:create, %{
          name: "Test Tech",
          phone: "512-555-0001",
          zone: :nw,
          pay_rate_cents: 2500,
          active: true
        })
        |> Ash.create()

      assert tech.name == "Test Tech"
      assert tech.zone == :nw
      assert tech.active == true
    end

    test "toggling active flips the flag" do
      {:ok, tech} =
        MobileCarWash.Operations.Technician
        |> Ash.Changeset.for_create(:create, %{name: "Toggle Tech", active: true})
        |> Ash.create()

      {:ok, deactivated} =
        tech
        |> Ash.Changeset.for_update(:update, %{active: false})
        |> Ash.update()

      assert deactivated.active == false
    end
  end
end
