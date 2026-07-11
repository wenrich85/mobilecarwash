defmodule MobileCarWash.Operations.TechInvitesTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.{TechApplication, TechInvite, TechInvites, Technician}

  require Ash.Query

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

  describe "create_admin_invite/2" do
    test "rejects an email that already belongs to a customer" do
      email = "existing-invite-#{System.unique_integer([:positive])}@example.com"

      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: email,
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Existing Customer",
        phone: "+15125551010"
      })
      |> Ash.create!(authorize?: false)

      assert {:error, :email_taken} =
               TechInvites.create_admin_invite(invite_attrs(%{email: email}))
    end

    test "creates technician account shell, accepted application, inactive technician, and pending invite" do
      assert {:ok, result} = TechInvites.create_admin_invite(invite_attrs())

      assert result.raw_token
      assert result.invite_url =~ "/tech/invite/#{result.raw_token}"

      assert result.customer.role == :technician
      assert result.customer.hashed_password == nil

      assert result.application.customer_id == result.customer.id
      assert result.application.source == :admin_invite
      assert result.application.status == :accepted
      assert result.application.accepted_pay_rate_cents == 3400

      assert result.technician.user_account_id == result.customer.id
      assert result.technician.name == "Invited Tech"
      assert result.technician.active == false
      assert result.technician.pay_rate_cents == 3400

      assert result.invite.customer_id == result.customer.id
      assert result.invite.technician_id == result.technician.id
      assert result.invite.status == :pending
      refute result.invite.token_hash == result.raw_token
    end
  end

  describe "accept_invite/3" do
    test "sets password, activates technician, and marks invite accepted" do
      {:ok, result} = TechInvites.create_admin_invite(invite_attrs())

      assert {:ok, accepted} =
               TechInvites.accept_invite(
                 result.raw_token,
                 "Accepted123!",
                 "Accepted123!"
               )

      assert accepted.invite.status == :accepted
      assert accepted.invite.accepted_at
      assert accepted.technician.active == true
      assert accepted.customer.hashed_password

      assert {:ok, signed_in} =
               Customer
               |> Ash.Query.for_read(:sign_in_with_password, %{
                 email: to_string(accepted.customer.email),
                 password: "Accepted123!"
               })
               |> Ash.read_one(authorize?: false)

      assert signed_in.id == accepted.customer.id
    end

    test "rejects an already accepted token" do
      {:ok, result} = TechInvites.create_admin_invite(invite_attrs())

      assert {:ok, _accepted} =
               TechInvites.accept_invite(result.raw_token, "Accepted123!", "Accepted123!")

      assert {:error, :invite_not_pending} =
               TechInvites.accept_invite(result.raw_token, "Accepted123!", "Accepted123!")
    end

    test "rejects an expired pending token" do
      {:ok, result} = TechInvites.create_admin_invite(invite_attrs())

      result.invite
      |> Ash.Changeset.for_update(:update, %{
        expires_at: DateTime.add(DateTime.utc_now(), -1, :hour)
      })
      |> Ash.update!(authorize?: false)

      assert {:error, :invite_expired} =
               TechInvites.accept_invite(result.raw_token, "Accepted123!", "Accepted123!")
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

  defp invite_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        email: "admin-invite-#{System.unique_integer([:positive])}@example.com",
        name: "Invited Tech",
        phone: "+15125551020",
        home_zip: "78259",
        preferred_zone: :nw,
        availability_weekdays: true,
        availability_weekends: false,
        availability_mornings: true,
        availability_afternoons: true,
        availability_evenings: false,
        experience_level: :some,
        has_valid_driver_license: true,
        has_reliable_transportation: true,
        can_lift_supplies: true,
        desired_hours_per_week: 30,
        earliest_start_date: Date.utc_today(),
        emergency_contact_name: "Emergency Contact",
        emergency_contact_phone: "+15125551021",
        why_work_with_us: "Ready to serve customers.",
        experience_notes: "Weekend detailing.",
        schedule_notes: "Mornings preferred.",
        accepted_pay_rate_cents: 3400,
        accepted_pay_rate_pct: nil,
        assigned_zone: :nw,
        active: false
      },
      overrides
    )
  end
end
