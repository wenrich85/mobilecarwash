defmodule MobileCarWashWeb.Plugs.EnforceAccountActiveTest do
  @moduledoc """
  Slice E3: the EnforceAccountActive plug boots disabled customers
  out of any signed-in session. Browser requests get redirected to
  /sign-in with a flash; API requests get 401 {"error":
  "account_disabled"}.
  """
  use MobileCarWashWeb.ConnCase, async: false

  alias MobileCarWash.Accounts.Customer

  defp register_customer! do
    {:ok, c} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "disable-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Disable Target",
        phone:
          "+1512555#{:rand.uniform(9999) |> Integer.to_string() |> String.pad_leading(4, "0")}"
      })
      |> Ash.create()

    c
  end

  defp disable!(customer, reason \\ "Abuse of service") do
    customer
    |> Ash.Changeset.for_update(:disable, %{reason: reason})
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

  describe "Customer :disable action" do
    test "stamps disabled_at and a required reason" do
      c = register_customer!()
      disabled = disable!(c, "Repeated no-shows")

      assert disabled.disabled_at
      assert disabled.disabled_reason == "Repeated no-shows"
    end

    test "blank reason is rejected" do
      c = register_customer!()

      {:error, %Ash.Error.Invalid{}} =
        c
        |> Ash.Changeset.for_update(:disable, %{reason: "   "})
        |> Ash.update(authorize?: false)
    end

    test ":reenable clears disabled_at and disabled_reason" do
      c = register_customer!()
      disabled = disable!(c, "Temporary")

      {:ok, reenabled} =
        disabled
        |> Ash.Changeset.for_update(:reenable, %{})
        |> Ash.update(authorize?: false)

      assert is_nil(reenabled.disabled_at)
      assert is_nil(reenabled.disabled_reason)
    end
  end

  describe "browser sessions" do
    test "signed-in disabled customer is kicked to /sign-in on next request",
         %{conn: conn} do
      c = register_customer!()
      authed = sign_in(conn, c)

      # Disable and hit an authenticated route.
      _ = disable!(c)
      conn = get(authed, ~p"/appointments")

      assert redirected_to(conn) == "/sign-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "disabled"
    end

    test "active (non-disabled) customer is not affected", %{conn: conn} do
      c = register_customer!()
      authed = sign_in(conn, c)

      # Not disabled — /appointments renders (200), not a sign-in redirect.
      conn = get(authed, ~p"/appointments")
      assert conn.status == 200
    end
  end

  describe "api requests" do
    test "disabled customer JWT gets 401 account_disabled", %{conn: conn} do
      c = register_customer!()

      # Register via API to get a valid JWT.
      body = %{
        "email" => "api-disable-#{System.unique_integer([:positive])}@test.com",
        "password" => "Password123!",
        "name" => "API Disable Target",
        "phone" => "+15125559000"
      }

      reg_conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/auth/register", body)

      assert %{"token" => token, "customer" => %{"id" => api_id}} = json_response(reg_conn, 201)

      # Disable that customer.
      {:ok, api_customer} = Ash.get(Customer, api_id, authorize?: false)
      _ = disable!(api_customer)

      # Now hit an authed API endpoint.
      resp_conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/v1/appointments")

      assert json_response(resp_conn, 401) == %{"error" => "account_disabled"}

      # Unused var (silence warnings when test helpers change).
      _ = c
    end
  end
end
