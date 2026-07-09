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

  defp application_attrs(overrides \\ %{}) do
    Map.merge(
      %{
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
      },
      overrides
    )
  end

  defp create_application!(customer, overrides \\ %{}) do
    TechApplication
    |> Ash.Changeset.for_create(:create, application_attrs(overrides))
    |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
    |> Ash.create!(authorize?: false)
  end

  describe "ownership" do
    test "public create does not accept customer_id" do
      customer = customer_fixture()

      result =
        TechApplication
        |> Ash.Changeset.for_create(
          :create,
          Map.put(application_attrs(), :customer_id, customer.id)
        )
        |> Ash.create(authorize?: false)

      assert {:error, _} = result
    end

    test "application requires a customer relationship" do
      result =
        TechApplication
        |> Ash.Changeset.for_create(:create, application_attrs())
        |> Ash.create(authorize?: false)

      assert {:error, _} = result
    end
  end

  describe "application lifecycle" do
    test "customer can create and submit a draft application" do
      customer = customer_fixture()
      application = create_application!(customer)

      assert application.status == :draft

      {:ok, submitted} =
        application
        |> Ash.Changeset.for_update(:submit, %{})
        |> Ash.update(authorize?: false)

      assert submitted.status == :pending_review
      assert submitted.submitted_at
    end

    test "save_draft updates fields only while draft" do
      customer = customer_fixture()
      application = create_application!(customer)

      {:ok, saved} =
        application
        |> Ash.Changeset.for_update(:save_draft, %{schedule_notes: "Updated while drafting"})
        |> Ash.update(authorize?: false)

      assert saved.status == :draft
      assert saved.schedule_notes == "Updated while drafting"

      {:ok, submitted} =
        saved
        |> Ash.Changeset.for_update(:submit, %{})
        |> Ash.update(authorize?: false)

      assert {:error, _} =
               submitted
               |> Ash.Changeset.for_update(:save_draft, %{schedule_notes: "Should be rejected"})
               |> Ash.update(authorize?: false)
    end

    test "mark_reviewed only works from pending_review" do
      customer = customer_fixture()
      draft = create_application!(customer)

      assert {:error, _} =
               draft
               |> Ash.Changeset.for_update(:mark_reviewed, %{review_notes: "Too early"})
               |> Ash.update(authorize?: false)

      {:ok, submitted} =
        draft
        |> Ash.Changeset.for_update(:submit, %{})
        |> Ash.update(authorize?: false)

      {:ok, reviewed} =
        submitted
        |> Ash.Changeset.for_update(:mark_reviewed, %{review_notes: "Ready for decision"})
        |> Ash.update(authorize?: false)

      assert reviewed.status == :reviewed
      assert reviewed.review_notes == "Ready for decision"
      assert reviewed.reviewed_at
    end

    test "accepting requires reviewed status and promotes customer" do
      customer = customer_fixture()

      draft =
        create_application!(customer, %{preferred_name: "Accepted Tech", preferred_zone: :se})

      assert {:error, _} =
               draft
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

      {:ok, reviewed} =
        draft
        |> Ash.Changeset.for_update(:submit, %{})
        |> Ash.update(authorize?: false)
        |> then(fn {:ok, submitted} ->
          submitted
          |> Ash.Changeset.for_update(:mark_reviewed, %{review_notes: "Strong applicant."})
          |> Ash.update(authorize?: false)
        end)

      {:ok, accepted} =
        reviewed
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
      assert technician.phone == "+15125550100"
      assert technician.zone == :se
      assert technician.pay_rate_cents == 3000
      assert technician.active == true
    end

    test "not_accept leaves customer role unchanged and requires reviewed status" do
      customer = customer_fixture()

      draft =
        create_application!(customer, %{preferred_name: "Declined Applicant", preferred_zone: :ne})

      assert {:error, _} =
               draft
               |> Ash.Changeset.for_update(:not_accept, %{
                 review_notes: "Needs valid license first.",
                 decision_note: "Please apply again when your license is active."
               })
               |> Ash.update(authorize?: false)

      {:ok, reviewed} =
        draft
        |> Ash.Changeset.for_update(:submit, %{})
        |> Ash.update(authorize?: false)
        |> then(fn {:ok, submitted} ->
          submitted
          |> Ash.Changeset.for_update(:mark_reviewed, %{
            review_notes: "Needs valid license first."
          })
          |> Ash.update(authorize?: false)
        end)

      {:ok, declined} =
        reviewed
        |> Ash.Changeset.for_update(:not_accept, %{
          review_notes: "Needs valid license first.",
          decision_note: "Please apply again when your license is active."
        })
        |> Ash.update(authorize?: false)

      assert declined.status == :not_accepted
      assert declined.decided_at
      assert Ash.get!(Customer, customer.id, authorize?: false).role == :customer
    end
  end

  describe "for_customer read action" do
    test "returns only the application for the given customer" do
      customer = customer_fixture()
      other_customer = customer_fixture()

      application = create_application!(customer)

      _other_application =
        create_application!(other_customer, %{preferred_name: "Other Applicant"})

      {:ok, applications} =
        TechApplication
        |> Ash.Query.for_read(:for_customer, %{customer_id: customer.id})
        |> Ash.read(authorize?: false)

      assert Enum.map(applications, & &1.id) == [application.id]
    end
  end
end
