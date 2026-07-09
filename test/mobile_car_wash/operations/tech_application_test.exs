defmodule MobileCarWash.Operations.TechApplicationTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.{TechApplication, Technician}

  defp customer_fixture do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "tech-applicant-#{System.unique_integer([:positive])}@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Applicant One",
        phone: "+15125550100"
      })
      |> Ash.create()

    customer
  end

  describe "application lifecycle" do
    test "customer can create and submit a draft application" do
      customer = customer_fixture()

      {:ok, application} =
        TechApplication
        |> Ash.Changeset.for_create(:create, %{
          preferred_name: "App One",
          phone: "+15125550100",
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
          desired_hours_per_week: 20,
          earliest_start_date: Date.utc_today(),
          emergency_contact_name: "Backup Person",
          emergency_contact_phone: "+15125550101",
          why_work_with_us: "I like clean cars and field work.",
          experience_notes: "Weekend detailing for neighbors.",
          schedule_notes: "Prefer mornings."
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
        |> Ash.create(authorize?: false)

      assert application.status == :draft

      {:ok, submitted} =
        application
        |> Ash.Changeset.for_update(:submit, %{})
        |> Ash.update(authorize?: false)

      assert submitted.status == :pending_review
      assert submitted.submitted_at
    end

    test "accepting promotes customer and creates linked technician" do
      customer = customer_fixture()

      {:ok, application} =
        TechApplication
        |> Ash.Changeset.for_create(:create, %{
          preferred_name: "Accepted Tech",
          phone: "+15125550102",
          home_zip: "78259",
          preferred_zone: :se,
          availability_weekdays: true,
          availability_weekends: true,
          availability_mornings: true,
          availability_afternoons: false,
          availability_evenings: false,
          experience_level: :professional,
          has_valid_driver_license: true,
          has_reliable_transportation: true,
          can_lift_supplies: true,
          desired_hours_per_week: 30,
          earliest_start_date: Date.utc_today(),
          emergency_contact_name: "Emergency Contact",
          emergency_contact_phone: "+15125550103",
          why_work_with_us: "I want consistent work.",
          experience_notes: "Two years of mobile detailing.",
          schedule_notes: "Weekdays preferred."
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
        |> Ash.create(authorize?: false)

      {:ok, accepted} =
        application
        |> Ash.Changeset.for_update(:accept, %{
          review_notes: "Strong applicant.",
          decision_note: "Welcome aboard.",
          accepted_pay_rate_cents: 3000,
          accepted_pay_rate_pct: nil,
          assigned_zone: :se,
          van_id: nil,
          active: true
        })
        |> Ash.update(authorize?: false)

      assert accepted.status == :accepted
      assert accepted.decided_at

      reloaded_customer = Ash.get!(Customer, customer.id, authorize?: false)
      assert reloaded_customer.role == :technician

      technicians = Ash.read!(Technician, authorize?: false)
      technician = Enum.find(technicians, &(&1.user_account_id == customer.id))
      assert technician.name == "Accepted Tech"
      assert technician.phone == "+15125550102"
      assert technician.zone == :se
      assert technician.pay_rate_cents == 3000
      assert technician.active == true
    end

    test "not_accept leaves customer role unchanged" do
      customer = customer_fixture()

      {:ok, application} =
        TechApplication
        |> Ash.Changeset.for_create(:create, %{
          preferred_name: "Declined Applicant",
          phone: "+15125550104",
          home_zip: "78259",
          preferred_zone: :ne,
          availability_weekdays: false,
          availability_weekends: true,
          availability_mornings: false,
          availability_afternoons: true,
          availability_evenings: true,
          experience_level: :none,
          has_valid_driver_license: false,
          has_reliable_transportation: true,
          can_lift_supplies: true,
          desired_hours_per_week: 10,
          earliest_start_date: Date.utc_today(),
          emergency_contact_name: "Emergency Contact",
          emergency_contact_phone: "+15125550105",
          why_work_with_us: "I want to learn.",
          experience_notes: "No prior experience.",
          schedule_notes: "Weekends only."
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
        |> Ash.create(authorize?: false)

      {:ok, declined} =
        application
        |> Ash.Changeset.for_update(:not_accept, %{
          review_notes: "Needs valid license first.",
          decision_note: "Please apply again when your license is active."
        })
        |> Ash.update(authorize?: false)

      assert declined.status == :not_accepted
      assert Ash.get!(Customer, customer.id, authorize?: false).role == :customer
    end
  end
end
