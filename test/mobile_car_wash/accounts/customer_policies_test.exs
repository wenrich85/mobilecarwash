defmodule MobileCarWash.Accounts.CustomerPoliciesTest do
  @moduledoc """
  Regression tests for the Customer resource's authorization policies.

  These exist because the SECURITY_AUDIT_REPORT flagged a time when every
  Customer action was gated by `authorize_if always()` — any signed-in
  actor could read/update/delete any other customer. Current policies
  restrict:

    * :read / :update — actor must be the customer themselves or an admin
    * :destroy         — admins only

  A sloppy future refactor that re-introduces a blanket policy should
  break one of these tests.
  """
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Accounts.Customer

  defp register_customer(opts \\ []) do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: opts[:email] || "policy-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: opts[:name] || "Policy Test",
        phone: opts[:phone] || "+15125551000"
      })
      |> Ash.create()

    if opts[:role] do
      customer
      |> Ash.Changeset.for_update(:update, %{role: opts[:role]})
      |> Ash.update!(authorize?: false)
    else
      customer
    end
  end

  describe ":read" do
    test "a customer can read their own record" do
      me = register_customer()

      {:ok, loaded} = Ash.get(Customer, me.id, actor: me)
      assert loaded.id == me.id
    end

    test "a customer CANNOT read another customer's record" do
      me = register_customer()
      other = register_customer(email: "other@test.com")

      # Ash's policy engine surfaces this as NotFound rather than Forbidden
      # so existence isn't leaked by the error type. Either is a pass — the
      # guarantee is the actor doesn't see the other customer's data.
      result = Ash.get(Customer, other.id, actor: me)

      assert match?({:error, %Ash.Error.Invalid{}}, result) or
               match?({:error, %Ash.Error.Forbidden{}}, result),
             "expected unauthorized read to fail, got: #{inspect(result)}"
    end

    test "a customer's cross-customer query returns an empty list, not the row" do
      require Ash.Query

      me = register_customer()
      other = register_customer(email: "other-list@test.com")

      {:ok, rows} =
        Customer
        |> Ash.Query.filter(id == ^other.id)
        |> Ash.read(actor: me)

      assert rows == []
    end

    test "an admin CAN read any customer's record" do
      admin = register_customer(email: "admin-read@test.com", role: :admin)
      other = register_customer(email: "target-read@test.com")

      {:ok, loaded} = Ash.get(Customer, other.id, actor: admin)
      assert loaded.id == other.id
    end
  end

  describe ":update" do
    test "a customer can update their own record" do
      me = register_customer()

      {:ok, updated} =
        me
        |> Ash.Changeset.for_update(:update, %{name: "Renamed"})
        |> Ash.update(actor: me)

      assert updated.name == "Renamed"
    end

    test "a customer CANNOT update another customer's record" do
      me = register_customer()
      other = register_customer(email: "other-update@test.com")

      result =
        other
        |> Ash.Changeset.for_update(:update, %{name: "Hijacked"})
        |> Ash.update(actor: me)

      assert match?({:error, %Ash.Error.Forbidden{}}, result),
             "updating another customer's record must be forbidden"
    end

    test "an admin CAN update any customer's record" do
      admin = register_customer(email: "admin-update@test.com", role: :admin)
      other = register_customer(email: "target-update@test.com")

      {:ok, updated} =
        other
        |> Ash.Changeset.for_update(:update, %{name: "Admin Renamed"})
        |> Ash.update(actor: admin)

      assert updated.name == "Admin Renamed"
    end
  end

  describe ":destroy" do
    # Customer has no :destroy action at all today — `defaults [:read, update: :*]`
    # intentionally omits it. The destroy-type policy in the resource is a
    # defense-in-depth guard in case one's added later. Pin the current
    # "can't be destroyed" contract here.
    test "no :destroy action is exposed on the Customer resource" do
      destroy_actions =
        Customer
        |> Ash.Resource.Info.actions()
        |> Enum.filter(&(&1.type == :destroy))

      assert destroy_actions == [],
             """
             A :destroy action was added to Customer. Make sure the existing
             admin-only policy still covers it, then update this test to
             exercise the action directly (see customer_policies_test.exs
             history for the shape).
             """
    end
  end

  describe "bypassed auth actions" do
    # These actions must remain accessible without an actor — that's the
    # point of bypass policies. register/sign-in wouldn't work otherwise.
    test ":register_with_password works without an actor" do
      {:ok, customer} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "bypass-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Bypass Test",
          phone: "+15125552000"
        })
        |> Ash.create()

      assert customer.id
    end
  end
end
