defmodule MobileCarWashWeb.Admin.DispatchLiveKanbanTest do
  use MobileCarWashWeb.ConnCase

  setup do
    %{conn: build_conn()}
  end

  describe "Dispatch Kanban Implementation" do
    test "kanban_column component is available in DispatchComponents" do
      # Check that the component module exists and has the kanban_column function
      functions =
        MobileCarWashWeb.Admin.DispatchComponents.__info__(:functions)
        |> Enum.find(fn {name, _arity} -> name == :kanban_column end)

      refute is_nil(functions), "kanban_column component should be defined in DispatchComponents"
    end

    test "appointment_card component is still available" do
      # Verify the original appointment_card component still works
      functions =
        MobileCarWashWeb.Admin.DispatchComponents.__info__(:functions)
        |> Enum.find(fn {name, _arity} -> name == :appointment_card end)

      refute is_nil(functions), "appointment_card component should be defined"
    end

    test "dispatch page requires authentication", %{conn: conn} do
      conn = get(conn, "/admin/dispatch")
      assert redirected_to(conn) == "/sign-in"
    end
  end
end
