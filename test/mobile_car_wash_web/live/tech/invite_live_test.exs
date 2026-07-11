defmodule MobileCarWashWeb.Tech.InviteLiveTest do
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Operations.TechInvites

  test "valid pending token renders password setup form", %{conn: conn} do
    {:ok, invite} = TechInvites.create_admin_invite(invite_attrs())

    {:ok, view, html} = live(conn, "/tech/invite/#{invite.raw_token}")

    assert has_element?(view, "#tech-invite-form")
    assert html =~ "Invited Tech"
    assert html =~ "Set password"
  end

  test "password mismatch stays on setup page with an error", %{conn: conn} do
    {:ok, invite} = TechInvites.create_admin_invite(invite_attrs())

    {:ok, view, _html} = live(conn, "/tech/invite/#{invite.raw_token}")

    html =
      view
      |> form("#tech-invite-form", %{
        "invite" => %{
          "password" => "Accepted123!",
          "password_confirmation" => "Wrong123!"
        }
      })
      |> render_submit()

    assert html =~ "Could not set password"
    assert has_element?(view, "#tech-invite-form")
  end

  test "valid password activates invite and redirects to sign in", %{conn: conn} do
    {:ok, invite} = TechInvites.create_admin_invite(invite_attrs())

    {:ok, view, _html} = live(conn, "/tech/invite/#{invite.raw_token}")

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             view
             |> form("#tech-invite-form", %{
               "invite" => %{
                 "password" => "Accepted123!",
                 "password_confirmation" => "Accepted123!"
               }
             })
             |> render_submit()
  end

  test "invalid token renders invalid state", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/tech/invite/not-a-real-token")

    assert html =~ "setup link is invalid or expired"
  end

  test "expired token renders invalid state", %{conn: conn} do
    {:ok, invite} = TechInvites.create_admin_invite(invite_attrs())

    invite.invite
    |> Ash.Changeset.for_update(:update, %{
      expires_at: DateTime.add(DateTime.utc_now(), -1, :hour)
    })
    |> Ash.update!(authorize?: false)

    {:ok, _view, html} = live(conn, "/tech/invite/#{invite.raw_token}")

    assert html =~ "setup link is invalid or expired"
  end

  defp invite_attrs do
    %{
      email: "invite-live-#{System.unique_integer([:positive])}@example.com",
      name: "Invited Tech",
      phone: "+15125551200",
      home_zip: "78259",
      preferred_zone: :nw,
      availability_weekdays: true,
      availability_mornings: true,
      experience_level: :some,
      has_valid_driver_license: true,
      has_reliable_transportation: true,
      can_lift_supplies: true,
      desired_hours_per_week: 30,
      accepted_pay_rate_cents: 3400,
      assigned_zone: :nw
    }
  end
end
