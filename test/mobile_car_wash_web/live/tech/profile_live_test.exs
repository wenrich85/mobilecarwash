defmodule MobileCarWashWeb.Tech.ProfileLiveTest do
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.{TechApplication, TechInvites}

  defp customer_fixture(role \\ :customer) do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "tech-profile-#{System.unique_integer([:positive])}@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Profile Customer",
        phone: "+15125550300"
      })
      |> Ash.create()

    customer
    |> Ash.Changeset.for_update(:update, %{role: role})
    |> Ash.update!(authorize?: false)
  end

  defp sign_in(conn, customer, password \\ "Password123!") do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> post("/auth/customer/password/sign_in", %{
      "customer" => %{
        "email" => to_string(customer.email),
        "password" => password
      }
    })
    |> recycle()
  end

  defp create_application!(customer, attrs) do
    default_attrs = %{
      preferred_name: "Profile Applicant",
      phone: "+15125550300",
      home_zip: "78259",
      preferred_zone: :ne,
      availability_weekdays: true,
      availability_weekends: false,
      availability_mornings: true,
      availability_afternoons: false,
      availability_evenings: true,
      experience_level: :professional,
      has_valid_driver_license: true,
      has_reliable_transportation: true,
      can_lift_supplies: true,
      desired_hours_per_week: 30,
      earliest_start_date: ~D[2026-07-15],
      emergency_contact_name: "Casey Contact",
      emergency_contact_phone: "+15125550301",
      why_work_with_us: "I like customer-facing work.",
      experience_notes: "Five years of detailing experience.",
      schedule_notes: "Open weekday mornings."
    }

    TechApplication
    |> Ash.Changeset.for_create(:create, Map.merge(default_attrs, attrs))
    |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
    |> Ash.create!(authorize?: false)
  end

  defp submit_application!(application) do
    application
    |> Ash.Changeset.for_update(:submit, %{})
    |> Ash.update!(authorize?: false)
  end

  defp review_application!(application, review_notes) do
    application
    |> Ash.Changeset.for_update(:mark_reviewed, %{review_notes: review_notes})
    |> Ash.update!(authorize?: false)
  end

  defp accept_application!(application, attrs) do
    application
    |> Ash.Changeset.for_update(:accept, attrs)
    |> Ash.update!(authorize?: false)
  end

  test "anonymous visitors are redirected to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/tech/profile")
  end

  test "applicant profile shows status and demographics", %{conn: conn} do
    customer = customer_fixture()

    customer
    |> create_application!(%{
      preferred_name: "Jordan Applicant",
      home_zip: "78701",
      preferred_zone: :nw,
      availability_weekends: true,
      desired_hours_per_week: 24
    })
    |> submit_application!()

    {:ok, view, _html} =
      conn
      |> sign_in(customer)
      |> live(~p"/tech/profile")

    assert has_element?(view, "#tech-profile")
    assert has_element?(view, "#tech-profile-applicant")
    assert render(view) =~ "Pending review"
    assert render(view) =~ "Jordan Applicant"
    assert render(view) =~ "78701"
    assert render(view) =~ "NW"
    assert render(view) =~ "Professional"
    assert render(view) =~ "Weekdays, weekends"
    assert render(view) =~ "Mornings, evenings"
    assert render(view) =~ "Driver license"
    assert render(view) =~ "Reliable transportation"
  end

  test "reviewed applicant profile shows review notes", %{conn: conn} do
    customer = customer_fixture()

    customer
    |> create_application!(%{
      preferred_name: "Riley Reviewed",
      preferred_zone: :sw
    })
    |> submit_application!()
    |> review_application!("Strong customer service background.")

    {:ok, view, _html} =
      conn
      |> sign_in(customer)
      |> live(~p"/tech/profile")

    assert render(view) =~ "Reviewed"
    assert render(view) =~ "Review notes"
    assert render(view) =~ "Strong customer service background."
  end

  test "accepted technician profile shows pay, zone, and earnings snapshot", %{conn: conn} do
    customer = customer_fixture(:technician)

    customer
    |> create_application!(%{
      preferred_name: "Alex Accepted",
      preferred_zone: :se
    })
    |> submit_application!()
    |> review_application!("Strong applicant")
    |> accept_application!(%{
      decision_note: "Welcome aboard.",
      accepted_pay_rate_cents: 3200,
      assigned_zone: :se
    })

    {:ok, view, _html} =
      conn
      |> sign_in(customer)
      |> live(~p"/tech/profile")

    assert has_element?(view, "#tech-profile-technician")
    assert has_element?(view, "#tech-profile-earnings")
    assert render(view) =~ "Accepted"
    assert render(view) =~ "Alex Accepted"
    assert render(view) =~ "$32.00"
    assert render(view) =~ "SE"
    assert render(view) =~ "This pay period"
    assert render(view) =~ "Strong applicant"
    assert render(view) =~ "Decision note"
    assert render(view) =~ "Welcome aboard."
  end

  test "admin-invited technician profile shows admin invite pathway", %{conn: conn} do
    {:ok, invite} =
      TechInvites.create_admin_invite(%{
        email: "profile-invite-#{System.unique_integer([:positive])}@example.com",
        name: "Admin Invited",
        phone: "+15125550310",
        home_zip: "78259",
        preferred_zone: :nw,
        availability_weekdays: true,
        availability_mornings: true,
        experience_level: :some,
        has_valid_driver_license: true,
        has_reliable_transportation: true,
        can_lift_supplies: true,
        desired_hours_per_week: 32,
        accepted_pay_rate_cents: 3400,
        assigned_zone: :nw
      })

    {:ok, accepted} =
      TechInvites.accept_invite(invite.raw_token, "Accepted123!", "Accepted123!")

    {:ok, view, _html} =
      conn
      |> sign_in(accepted.customer, "Accepted123!")
      |> live(~p"/tech/profile")

    assert render(view) =~ "Admin invite"
    assert render(view) =~ "Admin Invited"
    assert render(view) =~ "$34.00"
    assert render(view) =~ "NW"
  end
end
