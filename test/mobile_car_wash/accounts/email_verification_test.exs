defmodule MobileCarWash.Accounts.EmailVerificationTest do
  @moduledoc """
  SECURITY_AUDIT_REPORT MEDIUM #6: no email verification on signup. A
  customer could register with someone else's email address and the app
  would happily send booking confirmations, password-reset tokens, and
  marketing mail to an unconfirmed address.

  Soft-gate approach (pins the current ship-before-April rule):

    * Customer has an `email_verified_at :utc_datetime_usec` attribute,
      nil on fresh accounts.
    * `:verify_email` update action takes a `:token` argument, confirms
      it, and sets `email_verified_at`. Idempotent — running it again
      on a verified account just no-ops.
    * Registration through any path (web or API) enqueues
      `VerificationEmailWorker` which mints a 24h verification JWT and
      sends the link via Email.verify_email/3.
    * Signing in / booking / paying is NOT blocked on verification —
      that's the "soft" part. A banner nudges the customer to verify
      but doesn't stop the flow.

  These tests pin: the attribute exists, the action works, and the
  after-action enqueues the worker on register.
  """
  use MobileCarWash.DataCase, async: false
  use Oban.Testing, repo: MobileCarWash.Repo

  alias MobileCarWash.Accounts.{Customer, EmailVerification}

  defp register_customer do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "verify-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Verify Me",
        phone: "+15125553000"
      })
      |> Ash.create()

    customer
  end

  describe "email_verified_at attribute" do
    test "defaults to nil on a freshly-registered customer" do
      customer = register_customer()
      assert is_nil(customer.email_verified_at)
    end
  end

  describe ":verify_email action" do
    test "with a valid token sets email_verified_at to now" do
      customer = register_customer()
      token = EmailVerification.mint_token(customer)

      before = DateTime.utc_now()

      {:ok, verified} =
        customer
        |> Ash.Changeset.for_update(:verify_email, %{token: token})
        |> Ash.update(authorize?: false)

      assert verified.email_verified_at
      assert DateTime.compare(verified.email_verified_at, before) != :lt
    end

    test "rejects an expired token" do
      customer = register_customer()
      token = EmailVerification.mint_token(customer, expires_in: -60)

      assert {:error, _} =
               customer
               |> Ash.Changeset.for_update(:verify_email, %{token: token})
               |> Ash.update(authorize?: false)

      {:ok, reloaded} = Ash.get(Customer, customer.id, authorize?: false)
      assert is_nil(reloaded.email_verified_at)
    end

    test "rejects a token for a different customer" do
      alice = register_customer()
      bob = register_customer()

      token_for_alice = EmailVerification.mint_token(alice)

      assert {:error, _} =
               bob
               |> Ash.Changeset.for_update(:verify_email, %{token: token_for_alice})
               |> Ash.update(authorize?: false)
    end

    test "rejects a token minted against a different email" do
      customer = register_customer()
      old_email = to_string(customer.email)
      token = EmailVerification.mint_token(customer)

      # Customer changes email before clicking the link
      {:ok, _} =
        customer
        |> Ash.Changeset.for_update(:update, %{email: "new-#{:rand.uniform(10_000)}@test.com"})
        |> Ash.update(authorize?: false)

      reloaded = Ash.get!(Customer, customer.id, authorize?: false)
      refute to_string(reloaded.email) == old_email

      assert {:error, _} =
               reloaded
               |> Ash.Changeset.for_update(:verify_email, %{token: token})
               |> Ash.update(authorize?: false)
    end
  end

  describe "register_with_password enqueues the verification worker" do
    test "a fresh registration fires VerificationEmailWorker",
         %{} = _context do
      _customer = register_customer()

      assert_received {:email, email}
      assert email.subject =~ "verify" or email.subject =~ "Verify"
    end
  end
end
