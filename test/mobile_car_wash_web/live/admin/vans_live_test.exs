defmodule MobileCarWashWeb.Admin.VansLiveTest do
  @moduledoc """
  Tests for the admin Vans LiveView.
  """
  use MobileCarWashWeb.ConnCase, async: true

  describe "auth guard" do
    test "non-authenticated user is redirected to sign-in", %{conn: conn} do
      conn = get(conn, ~p"/admin/vans")
      assert redirected_to(conn) == "/sign-in"
    end
  end

  describe "van resource" do
    test "can create a van", _context do
      {:ok, van} =
        MobileCarWash.Operations.Van
        |> Ash.Changeset.for_create(:create, %{
          name: "Test Van",
          license_plate: "ABC123",
          active: true
        })
        |> Ash.create()

      assert van.name == "Test Van"
      assert van.license_plate == "ABC123"
      assert van.active == true
    end

    test "can update a van", _context do
      {:ok, van} =
        MobileCarWash.Operations.Van
        |> Ash.Changeset.for_create(:create, %{
          name: "Original Van",
          license_plate: "OLD123",
          active: true
        })
        |> Ash.create()

      {:ok, updated} =
        van
        |> Ash.Changeset.for_update(:update, %{
          name: "Updated Van",
          license_plate: "NEW456"
        })
        |> Ash.update()

      assert updated.name == "Updated Van"
      assert updated.license_plate == "NEW456"
    end

    test "can toggle van active status", _context do
      {:ok, van} =
        MobileCarWash.Operations.Van
        |> Ash.Changeset.for_create(:create, %{
          name: "Test Van",
          license_plate: "ABC123",
          active: true
        })
        |> Ash.create()

      {:ok, deactivated} =
        van
        |> Ash.Changeset.for_update(:update, %{active: false})
        |> Ash.update()

      assert deactivated.active == false

      {:ok, reactivated} =
        deactivated
        |> Ash.Changeset.for_update(:update, %{active: true})
        |> Ash.update()

      assert reactivated.active == true
    end

    test "license plate is optional", _context do
      {:ok, van} =
        MobileCarWash.Operations.Van
        |> Ash.Changeset.for_create(:create, %{
          name: "Van Without Plate",
          license_plate: ""
        })
        |> Ash.create()

      assert van.name == "Van Without Plate"
      assert van.license_plate == nil
    end

    test "can list all vans", _context do
      {:ok, _van1} =
        MobileCarWash.Operations.Van
        |> Ash.Changeset.for_create(:create, %{
          name: "Van 1",
          license_plate: "ABC123"
        })
        |> Ash.create()

      {:ok, _van2} =
        MobileCarWash.Operations.Van
        |> Ash.Changeset.for_create(:create, %{
          name: "Van 2",
          license_plate: "XYZ789"
        })
        |> Ash.create()

      vans = MobileCarWash.Operations.Van |> Ash.read!()
      assert length(vans) >= 2
    end
  end
end
