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
end
