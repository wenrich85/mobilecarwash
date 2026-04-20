defmodule MobileCarWashWeb.AppointmentsShareCardTest do
  @moduledoc """
  Marketing Phase 2E / Slice 3: customer-facing "Share & earn" card
  on /appointments. Shows the customer's referral link + running
  credit balance, with a copy-to-clipboard button.
  """
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer

  defp register! do
    {:ok, c} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "share-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Share Test",
        phone: "+15125556500"
      })
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

  test "renders share link and credit balance for the signed-in customer",
       %{conn: conn} do
    customer = register!()

    {:ok, customer} =
      customer
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.force_change_attribute(:referral_credit_cents, 2_500)
      |> Ash.update(authorize?: false)

    conn = sign_in(conn, customer)
    {:ok, _lv, html} = live(conn, ~p"/appointments")

    assert html =~ customer.referral_code
    assert html =~ "ref=#{customer.referral_code}"
    # $25.00 credit
    assert html =~ "25" and html =~ "credit"
  end
end
