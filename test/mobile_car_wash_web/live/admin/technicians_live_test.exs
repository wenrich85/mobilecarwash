defmodule MobileCarWashWeb.Admin.TechniciansLiveTest do
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.{TechApplication, Technician}

  require Ash.Query

  test "admin can invite a technician account from technician index", %{conn: conn} do
    admin = user_fixture(:admin)

    {:ok, view, _html} =
      conn
      |> sign_in(admin)
      |> live("/admin/technicians")

    assert has_element?(view, "#admin-tech-invite-form")

    html =
      view
      |> form("#admin-tech-invite-form", %{
        "invite" => %{
          "email" => "new-tech@example.com",
          "name" => "New Tech",
          "phone" => "+15125551300",
          "home_zip" => "78259",
          "preferred_zone" => "nw",
          "availability_weekdays" => "true",
          "availability_mornings" => "true",
          "has_valid_driver_license" => "true",
          "has_reliable_transportation" => "true",
          "can_lift_supplies" => "true",
          "desired_hours_per_week" => "28",
          "accepted_pay_rate_cents" => "3600",
          "assigned_zone" => "nw"
        }
      })
      |> render_submit()

    assert html =~ "Technician invite created"
    assert html =~ "/tech/invite/"
    assert html =~ "Pending invite"
    assert html =~ "new-tech@example.com"

    customer =
      Customer
      |> Ash.Query.for_read(:by_email, %{email: "new-tech@example.com"})
      |> Ash.read_one!(authorize?: false)

    assert customer.role == :technician
    assert customer.hashed_password == nil

    application =
      TechApplication
      |> Ash.Query.for_read(:for_customer, %{customer_id: customer.id})
      |> Ash.read_one!(authorize?: false)

    assert application.source == :admin_invite
    assert application.status == :accepted

    technician =
      Technician
      |> Ash.Query.for_read(:for_user_account, %{user_account_id: customer.id})
      |> Ash.read_one!(authorize?: false)

    assert technician.active == false
    assert technician.pay_rate_cents == 3600
  end

  test "admin sees duplicate email error without creating a technician", %{conn: conn} do
    admin = user_fixture(:admin)

    Customer
    |> Ash.Changeset.for_create(:register_with_password, %{
      email: "duplicate-tech@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      name: "Existing",
      phone: "+15125551310"
    })
    |> Ash.create!(authorize?: false)

    {:ok, view, _html} =
      conn
      |> sign_in(admin)
      |> live("/admin/technicians")

    html =
      view
      |> form("#admin-tech-invite-form", %{
        "invite" => %{
          "email" => "duplicate-tech@example.com",
          "name" => "Duplicate Tech",
          "phone" => "+15125551311",
          "home_zip" => "78259",
          "preferred_zone" => "nw",
          "accepted_pay_rate_cents" => "3600",
          "assigned_zone" => "nw"
        }
      })
      |> render_submit()

    assert html =~ "Email already belongs to an account"

    assert Technician
           |> Ash.Query.filter(name == "Duplicate Tech")
           |> Ash.read!(authorize?: false) == []
  end

  defp user_fixture(role) do
    {:ok, user} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "#{role}-tech-index-#{System.unique_integer([:positive])}@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "#{role} user",
        phone: "+15125551320"
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
end
