defmodule MobileCarWashWeb.Admin.CustomersLiveTest do
  @moduledoc """
  Admin customer list + detail pages.

  The detail page was the missing affordance for retroactively tagging
  offline acquisitions (word-of-mouth, door hangers) identified in the
  original Marketing Phase 1 plan.
  """
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Marketing
  alias MobileCarWash.Marketing.{AcquisitionChannel, Persona, PersonaMembership}

  defp register_admin! do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "cdet-admin-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Customer Detail Admin",
        phone: "+15125557500"
      })
      |> Ash.create()

    customer
    |> Ash.Changeset.for_update(:update, %{role: :admin})
    |> Ash.update!(authorize?: false)
  end

  defp register_customer!(channel_id \\ nil) do
    attrs = %{
      email: "c-#{System.unique_integer([:positive])}@test.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      name: "Target Customer",
      phone: "+15125553#{:rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")}"
    }

    attrs = if channel_id, do: Map.put(attrs, :acquired_channel_id, channel_id), else: attrs

    {:ok, c} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, attrs)
      |> Ash.create()

    c
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
    test "anonymous → sign-in (list)", %{conn: conn} do
      conn = get(conn, ~p"/admin/customers")
      assert redirected_to(conn) == "/sign-in"
    end

    test "anonymous → sign-in (detail)", %{conn: conn} do
      conn = get(conn, ~p"/admin/customers/#{Ecto.UUID.generate()}")
      assert redirected_to(conn) == "/sign-in"
    end
  end

  describe "list" do
    test "shows every customer with name + email", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers")

      assert html =~ target.name
      assert html =~ to_string(target.email)
    end

    test "search narrows by name or email", %{conn: conn} do
      admin = register_admin!()
      needle = register_customer!()

      {:ok, _haystack} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "other-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Other Entirely Different",
          phone: "+15125554321"
        })
        |> Ash.create()

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers")

      html =
        lv
        |> form("#customer-search", %{"q" => needle.name})
        |> render_change()

      assert html =~ needle.name
      refute html =~ "Other Entirely Different"
    end
  end

  describe "detail" do
    setup do
      :ok = Marketing.seed_channels!()

      {:ok, [door]} =
        AcquisitionChannel
        |> Ash.Query.for_read(:by_slug, %{slug: "door_hangers"})
        |> Ash.read(authorize?: false)

      {:ok, [meta]} =
        AcquisitionChannel
        |> Ash.Query.for_read(:by_slug, %{slug: "meta_paid"})
        |> Ash.read(authorize?: false)

      %{door: door, meta: meta}
    end

    test "renders the customer's core profile", %{conn: conn, meta: meta} do
      admin = register_admin!()
      target = register_customer!(meta.id)

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/customers/#{target.id}")

      assert html =~ target.name
      assert html =~ to_string(target.email)
      assert html =~ "Meta"
    end

    test "reassign_channel updates acquired_channel_id",
         %{conn: conn, door: door, meta: meta} do
      admin = register_admin!()
      target = register_customer!(meta.id)

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers/#{target.id}")

      lv
      |> form("#reassign-channel", %{"channel_id" => door.id})
      |> render_submit()

      {:ok, reloaded} = Ash.get(Customer, target.id, authorize?: false)
      assert reloaded.acquired_channel_id == door.id
    end

    test "manually tagging a persona creates a membership", %{conn: conn} do
      admin = register_admin!()
      target = register_customer!()

      {:ok, persona} =
        Persona
        |> Ash.Changeset.for_create(:create, %{
          slug: "detail_persona",
          name: "Detail Persona",
          description: ""
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers/#{target.id}")

      lv
      |> form("#assign-persona", %{"persona_id" => persona.id})
      |> render_submit()

      {:ok, memberships} =
        PersonaMembership
        |> Ash.Query.for_read(:for_customer, %{customer_id: target.id})
        |> Ash.read(authorize?: false)

      assert length(memberships) == 1
      assert hd(memberships).persona_id == persona.id
      assert hd(memberships).manually_assigned == true
    end

    test "recompute_personas button runs the rule engine", %{conn: conn, meta: meta} do
      admin = register_admin!()
      target = register_customer!(meta.id)

      {:ok, _persona} =
        Persona
        |> Ash.Changeset.for_create(:create, %{
          slug: "meta_auto_#{System.unique_integer([:positive])}",
          name: "Meta Auto",
          description: "",
          criteria: %{"acquired_channel_slug" => "meta_paid"}
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/customers/#{target.id}")

      lv |> element("#recompute-personas") |> render_click()

      {:ok, memberships} =
        PersonaMembership
        |> Ash.Query.for_read(:for_customer, %{customer_id: target.id})
        |> Ash.read(authorize?: false)

      assert length(memberships) == 1
    end

    test "404s cleanly for a missing id", %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      assert {:error, {:live_redirect, %{to: "/admin/customers"}}} =
               live(conn, ~p"/admin/customers/#{Ecto.UUID.generate()}")
    end
  end
end
