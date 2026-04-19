defmodule MobileCarWashWeb.AuthControllerTest do
  @moduledoc """
  Covers the custom AuthController endpoints that aren't owned by
  AshAuthentication's generated routes — currently the email
  verify / resend flow.
  """
  use MobileCarWashWeb.ConnCase, async: false
  use Oban.Testing, repo: MobileCarWash.Repo

  alias MobileCarWash.Accounts.Customer

  # Swoosh test adapter sends `{:email, email}` to the test process on
  # every delivery. Drain them so `assert_received` below lands on the
  # email the resend flow actually fires, not residue from registration.
  defp flush_mailbox do
    receive do
      {:email, _} -> flush_mailbox()
    after
      0 -> :ok
    end
  end

  defp register_customer(opts \\ []) do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: opts[:email] || "resend-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Resend Test",
        phone: "+15125552001"
      })
      |> Ash.create()

    customer
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

  describe "POST /auth/resend-verification" do
    test "delivers a new verification email for an unverified signed-in customer",
         %{conn: conn} do
      customer = register_customer()

      # Oban runs inline in tests, so the register after_action already
      # fired its verification email. Drain the mailbox so the assert
      # below lands on the *resend*-triggered delivery.
      flush_mailbox()

      conn = sign_in(conn, customer) |> post("/auth/resend-verification")

      assert redirected_to(conn) =~ "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Verification email sent"

      assert_received {:email, email}
      assert email.subject =~ "Verify" or email.subject =~ "verify"
      assert Enum.any?(email.to, fn {_, addr} -> addr == to_string(customer.email) end)
    end

    test "no-ops silently for an already-verified customer", %{conn: conn} do
      customer = register_customer()

      {:ok, verified} =
        customer
        |> Ash.Changeset.for_update(:update, %{})
        |> Ash.Changeset.force_change_attribute(:email_verified_at, DateTime.utc_now())
        |> Ash.update(authorize?: false)

      conn = sign_in(conn, verified)
      flush_mailbox()

      conn = post(conn, "/auth/resend-verification")

      assert redirected_to(conn) =~ "/"
      # Same flash — we don't want to leak account state
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Verification email sent"

      # But no new email actually goes out
      refute_received {:email, _}
    end

    test "no-ops silently for an anonymous visitor", %{conn: conn} do
      flush_mailbox()

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> post("/auth/resend-verification")

      assert redirected_to(conn) =~ "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Verification email sent"

      refute_received {:email, _}
    end

    test "redirects back to the referer when it's a same-host path", %{conn: conn} do
      customer = register_customer()
      conn = sign_in(conn, customer)
      flush_mailbox()

      conn =
        conn
        |> put_req_header("referer", "http://www.example.com/appointments")
        |> post("/auth/resend-verification")

      assert redirected_to(conn) == "/appointments"
    end

    test "falls back to / for cross-host referers", %{conn: conn} do
      customer = register_customer()
      conn = sign_in(conn, customer)
      flush_mailbox()

      conn =
        conn
        |> put_req_header("referer", "https://evil.example/attack")
        |> post("/auth/resend-verification")

      assert redirected_to(conn) == "/"
    end
  end
end
