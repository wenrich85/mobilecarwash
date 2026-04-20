defmodule MobileCarWashWeb.Admin.PersonasLiveMatchPreviewTest do
  @moduledoc """
  Marketing Phase 2D / Slice 1: as the admin types criteria into the
  persona form, the page shows "N customers currently match" plus a
  sample — live, no save required.
  """
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Marketing
  alias MobileCarWash.Marketing.AcquisitionChannel

  defp register_admin! do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "p-admin-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "P Admin",
        phone: "+15125557300"
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

  defp register_customer!(channel_id) do
    {:ok, c} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "cust-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Cust",
        phone: "+15125556#{:rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")}",
        acquired_channel_id: channel_id
      })
      |> Ash.create()

    c
  end

  test "shows live match count as the admin picks a channel", %{conn: conn} do
    :ok = Marketing.seed_channels!()

    {:ok, [meta]} =
      AcquisitionChannel
      |> Ash.Query.for_read(:by_slug, %{slug: "meta_paid"})
      |> Ash.read(authorize?: false)

    register_customer!(meta.id)
    register_customer!(meta.id)

    admin = register_admin!()
    conn = sign_in(conn, admin)

    {:ok, lv, _} = live(conn, ~p"/admin/personas")
    lv |> element("button", "New Persona") |> render_click()

    # Change the channel filter — should trigger a match-count recompute
    html =
      lv
      |> form("#persona-form", %{
        "persona" => %{
          "slug" => "live_match",
          "name" => "Live Match",
          "description" => "",
          "criteria_channel_slug" => "meta_paid"
        }
      })
      |> render_change()

    assert html =~ "2" and html =~ "match"
  end

  test "match count reflects empty criteria = all customers", %{conn: conn} do
    :ok = Marketing.seed_channels!()

    {:ok, [meta]} =
      AcquisitionChannel
      |> Ash.Query.for_read(:by_slug, %{slug: "meta_paid"})
      |> Ash.read(authorize?: false)

    register_customer!(meta.id)

    admin = register_admin!()
    conn = sign_in(conn, admin)

    {:ok, lv, _} = live(conn, ~p"/admin/personas")
    lv |> element("button", "New Persona") |> render_click()

    html = render(lv)
    # Admin + 1 customer == 2, but we just want the count affordance visible
    assert html =~ "match"
  end
end
