defmodule MobileCarWash.Operations.TechInvitesTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.{TechApplication, TechInvite, Technician}

  describe "admin invite data model" do
    test "admin-created application records source and starts accepted" do
      {:ok, customer} =
        Customer
        |> Ash.Changeset.for_create(:create_technician_invitee, %{
          email: "invite-model-#{System.unique_integer([:positive])}@example.com",
          name: "Invite Model",
          phone: "+15125551000"
        })
        |> Ash.create(authorize?: false)

      {:ok, application} =
        TechApplication
        |> Ash.Changeset.for_create(:create_admin_invite, %{
          preferred_name: "Invite Model",
          phone: "+15125551000",
          home_zip: "78259",
          preferred_zone: :nw,
          desired_hours_per_week: 25,
          has_valid_driver_license: true,
          has_reliable_transportation: true,
          can_lift_supplies: true,
          accepted_pay_rate_cents: 3000,
          assigned_zone: :nw
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
        |> Ash.create(authorize?: false)

      assert application.source == :admin_invite
      assert application.status == :accepted
      assert application.decided_at
    end

    test "tech invite stores only a token hash and links account plus technician" do
      customer = create_invitee_customer!()
      technician = create_inactive_technician!(customer)

      {:ok, invite} =
        TechInvite
        |> Ash.Changeset.for_create(:create, %{
          token_hash: :crypto.hash(:sha256, "raw-token") |> Base.encode16(case: :lower),
          expires_at: DateTime.add(DateTime.utc_now(), 7, :day),
          customer_id: customer.id,
          technician_id: technician.id
        })
        |> Ash.create(authorize?: false)

      assert invite.status == :pending
      assert invite.customer_id == customer.id
      assert invite.technician_id == technician.id
      refute Map.has_key?(Map.from_struct(invite), :token)
    end
  end

  defp create_invitee_customer! do
    Customer
    |> Ash.Changeset.for_create(:create_technician_invitee, %{
      email: "invitee-#{System.unique_integer([:positive])}@example.com",
      name: "Invitee",
      phone: "+15125551001"
    })
    |> Ash.create!(authorize?: false)
  end

  defp create_inactive_technician!(customer) do
    Technician
    |> Ash.Changeset.for_create(:create, %{
      name: customer.name,
      phone: customer.phone,
      active: false,
      pay_rate_cents: 3000,
      zone: :nw
    })
    |> Ash.Changeset.force_change_attribute(:user_account_id, customer.id)
    |> Ash.create!(authorize?: false)
  end
end
