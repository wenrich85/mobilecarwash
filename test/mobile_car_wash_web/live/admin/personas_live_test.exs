defmodule MobileCarWashWeb.Admin.PersonasLiveTest do
  @moduledoc """
  Marketing Phase 2B / Slice 3: admin CRUD for Persona records.
  """
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Marketing.Persona

  defp register_admin! do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "p-admin-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "P Admin",
        phone: "+15125557200"
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

  describe "auth guard" do
    test "anonymous is redirected to sign-in", %{conn: conn} do
      conn = get(conn, ~p"/admin/personas")
      assert redirected_to(conn) == "/sign-in"
    end
  end

  describe "list view" do
    test "shows existing personas + an empty state", %{conn: conn} do
      admin = register_admin!()

      {:ok, _} =
        Persona
        |> Ash.Changeset.for_create(:create, %{
          slug: "busy_parent_list",
          name: "Busy Parent",
          description: "Harried parent"
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/personas")

      assert html =~ "Personas"
      assert html =~ "Busy Parent"
      assert html =~ "New Persona" or html =~ "new_persona" or html =~ "Create"
    end
  end

  describe "create form" do
    test "persists a new persona", %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      {:ok, lv, _html} = live(conn, ~p"/admin/personas")

      lv |> element("button", "New Persona") |> render_click()

      lv
      |> form("#persona-form", %{
        "persona" => %{
          "slug" => "weekend_warriors",
          "name" => "Weekend Warriors",
          "description" => "Car enthusiasts who detail every Saturday",
          "image_prompt" => "Auto detailer in driveway with polisher",
          "active" => "true"
        }
      })
      |> render_submit()

      {:ok, [created]} =
        Persona
        |> Ash.Query.for_read(:by_slug, %{slug: "weekend_warriors"})
        |> Ash.read(authorize?: false)

      assert created.name == "Weekend Warriors"
      assert created.image_prompt =~ "polisher"
    end

    test "rejects a duplicate slug with an error flash", %{conn: conn} do
      admin = register_admin!()

      {:ok, _} =
        Persona
        |> Ash.Changeset.for_create(:create, %{
          slug: "dupe_slug_live",
          name: "First",
          description: ""
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, lv, _html} = live(conn, ~p"/admin/personas")

      lv |> element("button", "New Persona") |> render_click()

      html =
        lv
        |> form("#persona-form", %{
          "persona" => %{
            "slug" => "dupe_slug_live",
            "name" => "Second",
            "description" => ""
          }
        })
        |> render_submit()

      assert html =~ "taken" or html =~ "exists" or html =~ "already" or html =~ "unique"
    end
  end

  describe "delete" do
    test "removes a persona", %{conn: conn} do
      admin = register_admin!()

      {:ok, persona} =
        Persona
        |> Ash.Changeset.for_create(:create, %{
          slug: "will_delete",
          name: "Will Delete",
          description: ""
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, lv, _html} = live(conn, ~p"/admin/personas")

      lv
      |> element("##{"delete-#{persona.id}"}")
      |> render_click()

      {:ok, rows} =
        Persona
        |> Ash.Query.for_read(:by_slug, %{slug: "will_delete"})
        |> Ash.read(authorize?: false)

      assert rows == []
    end
  end
end
