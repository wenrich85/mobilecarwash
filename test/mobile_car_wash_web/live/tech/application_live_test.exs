defmodule MobileCarWashWeb.Tech.ApplicationLiveTest do
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.TechApplication

  defp customer_fixture do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "apply-#{System.unique_integer([:positive])}@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Apply Customer",
        phone: "+15125550200"
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

  defp application_attrs do
    %{
      "preferred_name" => "Apply Customer",
      "phone" => "+15125550200",
      "home_zip" => "78259",
      "preferred_zone" => "nw",
      "availability_weekdays" => "true",
      "availability_weekends" => "false",
      "availability_mornings" => "true",
      "availability_afternoons" => "true",
      "availability_evenings" => "false",
      "experience_level" => "some",
      "has_valid_driver_license" => "true",
      "has_reliable_transportation" => "true",
      "can_lift_supplies" => "true",
      "desired_hours_per_week" => "20",
      "earliest_start_date" => Date.to_iso8601(Date.utc_today()),
      "emergency_contact_name" => "Emergency Person",
      "emergency_contact_phone" => "+15125550201",
      "why_work_with_us" => "I enjoy mobile work.",
      "experience_notes" => "Some detail work.",
      "schedule_notes" => "Mornings are best."
    }
  end

  defp create_application!(customer, attrs \\ %{}) do
    TechApplication
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(
        %{
          preferred_name: "Apply Customer",
          phone: "+15125550200",
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
          emergency_contact_name: "Emergency Person",
          emergency_contact_phone: "+15125550201",
          why_work_with_us: "I enjoy mobile work.",
          experience_notes: "Some detail work.",
          schedule_notes: "Mornings are best."
        },
        attrs
      )
    )
    |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
    |> Ash.create!(authorize?: false)
  end

  test "anonymous visitors are redirected to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/tech/apply")
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/tech/application")
  end

  test "signed-in customer can save a draft and submit it", %{conn: conn} do
    customer = customer_fixture()
    conn = sign_in(conn, customer)

    {:ok, view, _html} = live(conn, ~p"/tech/apply")
    assert has_element?(view, "#tech-application-form")

    view
    |> form("#tech-application-form", %{"application" => application_attrs()})
    |> render_submit()

    application =
      TechApplication
      |> Ash.Query.for_read(:for_customer, %{customer_id: customer.id})
      |> Ash.read_one!(authorize?: false)

    assert application.status == :draft

    view
    |> element("#submit-tech-application")
    |> render_click()

    application = Ash.get!(TechApplication, application.id, authorize?: false)
    assert application.status == :pending_review
    assert application.submitted_at
  end

  test "create ignores forged customer ownership params", %{conn: conn} do
    customer = customer_fixture()
    other_customer = customer_fixture()

    {:ok, view, _html} =
      conn
      |> sign_in(customer)
      |> live(~p"/tech/apply")

    view
    |> element("#tech-application-form")
    |> render_submit(%{
      "application" =>
        application_attrs()
        |> Map.put("customer_id", other_customer.id)
    })

    application =
      TechApplication
      |> Ash.Query.for_read(:for_customer, %{customer_id: customer.id})
      |> Ash.read_one!(authorize?: false)

    refute Ash.Query.for_read(TechApplication, :for_customer, %{customer_id: other_customer.id})
           |> Ash.read_one!(authorize?: false)

    assert application.customer_id == customer.id
  end

  test "submitted applicants are redirected from apply to the status page", %{conn: conn} do
    customer = customer_fixture()

    _application =
      create_application!(customer)
      |> then(&Ash.update!(Ash.Changeset.for_update(&1, :submit, %{}), authorize?: false))

    assert {:error, {:live_redirect, %{to: to}}} =
             conn
             |> sign_in(customer)
             |> live(~p"/tech/apply")

    assert to == "/tech/application"
  end

  test "draft status page keeps the continue application action available", %{conn: conn} do
    customer = customer_fixture()
    _application = create_application!(customer)

    {:ok, view, _html} =
      conn
      |> sign_in(customer)
      |> live(~p"/tech/application")

    assert has_element?(view, "#tech-application-status")
    assert has_element?(view, "#tech-application-status a[href='/tech/apply']")
    assert render(view) =~ "Draft"
  end

  test "status page shows submitted application status", %{conn: conn} do
    customer = customer_fixture()

    application =
      customer
      |> create_application!()
      |> then(&Ash.update!(Ash.Changeset.for_update(&1, :submit, %{}), authorize?: false))

    {:ok, view, _html} =
      conn
      |> sign_in(customer)
      |> live(~p"/tech/application")

    assert has_element?(view, "#tech-application-status")
    assert render(view) =~ "Pending review"
    assert render(view) =~ application.preferred_name
  end

  test "status page renders the application journey and applicant details", %{conn: conn} do
    customer = customer_fixture()

    _application =
      create_application!(customer, %{
        preferred_name: "Portal Applicant"
      })

    {:ok, view, _html} =
      conn
      |> sign_in(customer)
      |> live(~p"/tech/application")

    assert has_element?(view, "#tech-application-journey")
    assert has_element?(view, "#journey-step-draft[data-state='current']")
    assert has_element?(view, "#journey-step-pending_review[data-state='upcoming']")
    assert has_element?(view, "#journey-step-reviewed[data-state='upcoming']")
    assert has_element?(view, "#journey-step-decision[data-state='upcoming']")
    assert has_element?(view, "#tech-application-next-action a[href='/tech/apply']")
    assert has_element?(view, "#tech-application-details")
    assert render(view) =~ "Portal Applicant"
    refute render(view) =~ "Internal review note"
    refute render(view) =~ "Visible only after a final decision"
  end

  test "pending review status keeps admin review notes private", %{conn: conn} do
    customer = customer_fixture()

    application =
      create_application!(customer)
      |> then(&Ash.update!(Ash.Changeset.for_update(&1, :submit, %{}), authorize?: false))
      |> then(
        &Ash.update!(
          Ash.Changeset.for_update(&1, :mark_reviewed, %{review_notes: "Internal review note"}),
          authorize?: false
        )
      )

    {:ok, view, _html} =
      conn
      |> sign_in(customer)
      |> live(~p"/tech/application")

    assert application.status == :reviewed
    refute render(view) =~ "Internal review note"
    refute has_element?(view, "#tech-application-next-action a[href='/tech/profile']")
  end

  test "accepted status shows decision note and technician links", %{conn: conn} do
    customer = customer_fixture()

    application =
      create_application!(customer)
      |> then(&Ash.update!(Ash.Changeset.for_update(&1, :submit, %{}), authorize?: false))
      |> then(
        &Ash.update!(
          Ash.Changeset.for_update(&1, :mark_reviewed, %{review_notes: "Internal review note"}),
          authorize?: false
        )
      )
      |> then(
        &Ash.update!(
          Ash.Changeset.for_update(&1, :accept, %{
            review_notes: "Internal review note",
            decision_note: "Welcome aboard."
          }),
          authorize?: false
        )
      )

    {:ok, view, _html} =
      conn
      |> sign_in(customer)
      |> live(~p"/tech/application")

    assert application.status == :accepted
    assert has_element?(view, "#journey-step-decision[data-state='current']")
    assert render(view) =~ "Welcome aboard."
    assert has_element?(view, "#tech-application-next-action a[href='/tech/profile']")
    assert has_element?(view, "#tech-application-next-action a[href='/tech']")
  end

  test "not accepted status shows decision note without technician links", %{conn: conn} do
    customer = customer_fixture()

    application =
      create_application!(customer)
      |> then(&Ash.update!(Ash.Changeset.for_update(&1, :submit, %{}), authorize?: false))
      |> then(
        &Ash.update!(
          Ash.Changeset.for_update(&1, :mark_reviewed, %{review_notes: "Internal review note"}),
          authorize?: false
        )
      )
      |> then(
        &Ash.update!(
          Ash.Changeset.for_update(&1, :not_accept, %{
            review_notes: "Internal review note",
            decision_note: "Please apply again when your license is active."
          }),
          authorize?: false
        )
      )

    {:ok, view, _html} =
      conn
      |> sign_in(customer)
      |> live(~p"/tech/application")

    assert application.status == :not_accepted
    assert has_element?(view, "#journey-step-decision[data-state='current']")
    assert render(view) =~ "Please apply again when your license is active."
    refute render(view) =~ "Internal review note"
    refute has_element?(view, "#tech-application-next-action a[href='/tech/profile']")
    refute has_element?(view, "#tech-application-next-action a[href='/tech']")
  end
end
