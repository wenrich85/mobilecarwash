defmodule MobileCarWashWeb.Admin.TechApplicationsLiveTest do
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.{TechApplication, Technician}

  defp user_fixture(role) do
    {:ok, user} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "#{role}-#{System.unique_integer([:positive])}@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "#{role} user",
        phone: "+15125550300"
      })
      |> Ash.create()

    user
    |> Ash.Changeset.for_update(:update, %{role: role})
    |> Ash.update!(authorize?: false)
  end

  defp sign_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> post("/auth/customer/password/sign_in", %{
      "customer" => %{
        "email" => to_string(user.email),
        "password" => "Password123!"
      }
    })
    |> recycle()
  end

  defp application_fixture(customer) do
    {:ok, application} =
      TechApplication
      |> Ash.Changeset.for_create(:create, %{
        preferred_name: "Queue Applicant",
        phone: "+15125550301",
        home_zip: "78259",
        preferred_zone: :sw,
        availability_weekdays: true,
        availability_weekends: true,
        availability_mornings: true,
        availability_afternoons: false,
        availability_evenings: false,
        experience_level: :some,
        has_valid_driver_license: true,
        has_reliable_transportation: true,
        can_lift_supplies: true,
        desired_hours_per_week: 25,
        earliest_start_date: Date.utc_today(),
        emergency_contact_name: "Contact",
        emergency_contact_phone: "+15125550302",
        why_work_with_us: "I like detailing.",
        experience_notes: "Some detail work.",
        schedule_notes: "Weekdays."
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create(authorize?: false)

    application
    |> Ash.Changeset.for_update(:submit, %{})
    |> Ash.update!(authorize?: false)
  end

  test "non-admin cannot view application queue", %{conn: conn} do
    user = user_fixture(:customer)
    conn = sign_in(conn, user)

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/tech-applications")
  end

  test "admin can see pending applications", %{conn: conn} do
    admin = user_fixture(:admin)
    applicant = user_fixture(:customer)
    application_fixture(applicant)
    conn = sign_in(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/admin/tech-applications")

    assert has_element?(view, "#tech-applications")
    assert render(view) =~ "Queue Applicant"
    assert render(view) =~ "Pending review"
  end

  test "admin can accept an application and create technician", %{conn: conn} do
    admin = user_fixture(:admin)
    applicant = user_fixture(:customer)
    application = application_fixture(applicant)
    conn = sign_in(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/admin/tech-applications/#{application.id}")

    view
    |> form("#accept-tech-application-form", %{
      "decision" => %{
        "review_notes" => "Approved.",
        "decision_note" => "Welcome.",
        "accepted_pay_rate_cents" => "3500",
        "accepted_pay_rate_pct" => "",
        "assigned_zone" => "sw",
        "van_id" => "",
        "active" => "true"
      }
    })
    |> render_submit()

    application = Ash.get!(TechApplication, application.id, authorize?: false)
    assert application.status == :accepted
    assert application.reviewed_at
    assert application.decided_at

    reloaded = Ash.get!(Customer, applicant.id, authorize?: false)
    assert reloaded.role == :technician

    technician =
      Technician
      |> Ash.read!(authorize?: false)
      |> Enum.find(&(&1.user_account_id == applicant.id))

    assert technician
    assert technician.pay_rate_cents == 3500
    assert technician.zone == :sw
    assert technician.active == true
  end

  test "admin can mark an application reviewed with review notes", %{conn: conn} do
    admin = user_fixture(:admin)
    applicant = user_fixture(:customer)
    application = application_fixture(applicant)
    conn = sign_in(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/admin/tech-applications/#{application.id}")

    view
    |> form("#review-tech-application-form", %{
      "review" => %{
        "review_notes" => "Reviewed for interview readiness."
      }
    })
    |> render_submit()

    application = Ash.get!(TechApplication, application.id, authorize?: false)

    assert application.status == :reviewed
    assert application.reviewed_at
    assert application.review_notes == "Reviewed for interview readiness."
  end

  test "admin can decline a pending application with review and decision notes", %{conn: conn} do
    admin = user_fixture(:admin)
    applicant = user_fixture(:customer)
    application = application_fixture(applicant)
    conn = sign_in(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/admin/tech-applications/#{application.id}")

    view
    |> form("#not-accept-tech-application-form", %{
      "not_accept" => %{
        "review_notes" => "Attendance availability does not match demand.",
        "decision_note" => "We are moving forward with other applicants."
      }
    })
    |> render_submit()

    application = Ash.get!(TechApplication, application.id, authorize?: false)

    assert application.status == :not_accepted
    assert application.reviewed_at
    assert application.decided_at
    assert application.review_notes == "Attendance availability does not match demand."
    assert application.decision_note == "We are moving forward with other applicants."
  end
end
