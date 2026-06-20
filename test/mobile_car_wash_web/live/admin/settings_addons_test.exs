defmodule MobileCarWashWeb.Admin.SettingsAddonsTest do
  @moduledoc """
  Tests for the add-ons section of the admin Settings LiveView.
  Verifies that an admin can create an add-on and toggle its active state.
  """
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Scheduling.AddOn

  defp register_admin! do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "addons-admin-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "AddOns Admin",
        phone: "+15125557600"
      })
      |> Ash.create()

    customer
    |> Ash.Changeset.for_update(:update, %{role: :admin})
    |> Ash.update!(authorize?: false)
  end

  defp sign_in(conn, customer) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> post("/auth/customer/password/sign_in", %{
      "customer" => %{
        "email" => to_string(customer.email),
        "password" => "Password123!"
      }
    })
    |> recycle()
  end

  describe "add-ons tab" do
    test "admin can create an add-on", %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      {:ok, view, _} = live(conn, "/admin/settings")

      view
      |> element("button[phx-value-tab=add_ons]")
      |> render_click()

      view
      |> form("#add-on-form", add_on: %{name: "Clay Bar", slug: "clay_bar", price: "20"})
      |> render_submit()

      assert AddOn
             |> Ash.read!()
             |> Enum.any?(&(&1.slug == "clay_bar"))
    end

    test "admin can toggle an add-on active state", %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      {:ok, add_on} =
        AddOn
        |> Ash.Changeset.for_create(:create, %{
          name: "Wax Coat",
          slug: "wax_coat_toggle_#{System.unique_integer([:positive])}",
          price_cents: 1500,
          active: true
        })
        |> Ash.create()

      {:ok, view, _} = live(conn, "/admin/settings")

      view
      |> element("button[phx-value-tab=add_ons]")
      |> render_click()

      view
      |> element("button[phx-click='toggle_add_on'][phx-value-id='#{add_on.id}']")
      |> render_click()

      updated = Ash.get!(AddOn, add_on.id)
      assert updated.active == false
    end
  end
end
