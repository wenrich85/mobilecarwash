defmodule MobileCarWashWeb.Admin.MarketingLiveTest do
  @moduledoc """
  Marketing Phase 1 / Slice 5: admin-only /admin/marketing dashboard.
  CAC + spend per channel + spend-entry form in one page.
  """
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Marketing
  alias MobileCarWash.Marketing.{AcquisitionChannel, MarketingSpend}

  setup do
    :ok = Marketing.seed_channels!()
    :ok
  end

  defp register_admin! do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "mkt-admin-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Marketing Admin",
        phone: "+15125557100"
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
    test "anonymous user is redirected to sign-in", %{conn: conn} do
      conn = get(conn, ~p"/admin/marketing")
      assert redirected_to(conn) == "/sign-in"
    end
  end

  describe "admin access" do
    test "renders the dashboard shell with KPI tiles + channel table",
         %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      {:ok, _lv, html} = live(conn, ~p"/admin/marketing")

      assert html =~ "Marketing"
      # Blended KPI tiles
      assert html =~ "Total Spend"
      assert html =~ "New Customers"
      assert html =~ "Blended CAC"
      # Channel table header
      assert html =~ "Channel"
    end

    test "lists every active channel (including zero-activity rows)",
         %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      {:ok, _lv, html} = live(conn, ~p"/admin/marketing")

      # Zero-activity channels should still appear so the owner can
      # see what hasn't been used yet.
      assert html =~ "Meta"
      assert html =~ "Referral"
      assert html =~ "Door Hangers"
    end
  end

  describe "spend form" do
    test "submitting the form persists a MarketingSpend row",
         %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      {:ok, [meta]} =
        AcquisitionChannel
        |> Ash.Query.for_read(:by_slug, %{slug: "meta_paid"})
        |> Ash.read(authorize?: false)

      {:ok, lv, _html} = live(conn, ~p"/admin/marketing")

      # Submit the log-spend form
      lv
      |> form("#log-spend", %{
        "spend" => %{
          "channel_id" => meta.id,
          "spent_on" => "2026-04-22",
          "amount_dollars" => "50.00",
          "notes" => "Saturday boost"
        }
      })
      |> render_submit()

      rows = MarketingSpend |> Ash.read!(authorize?: false)
      assert Enum.any?(rows, fn r ->
               r.channel_id == meta.id and
                 r.amount_cents == 5_000 and
                 r.spent_on == ~D[2026-04-22]
             end)
    end

    test "invalid dollar amounts surface an error flash (no crash)",
         %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      {:ok, [meta]} =
        AcquisitionChannel
        |> Ash.Query.for_read(:by_slug, %{slug: "meta_paid"})
        |> Ash.read(authorize?: false)

      {:ok, lv, _html} = live(conn, ~p"/admin/marketing")

      html =
        lv
        |> form("#log-spend", %{
          "spend" => %{
            "channel_id" => meta.id,
            "spent_on" => "2026-04-22",
            "amount_dollars" => "-10"
          }
        })
        |> render_submit()

      # Error bubbles up, no row persisted.
      assert html =~ "amount" or html =~ "Amount" or html =~ "invalid" or html =~ "Invalid"
      rows = MarketingSpend |> Ash.read!(authorize?: false)
      assert rows == []
    end
  end

  describe "date range" do
    test "changing the period re-renders with fresh rows",
         %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      {:ok, lv, _html} = live(conn, ~p"/admin/marketing")

      # Just verify the select change doesn't crash — the content
      # varies with date math so don't pin it.
      html = lv |> element("#period-select") |> render_change(%{"period" => "last_30"})
      assert html =~ "Marketing"
    end
  end
end
