defmodule MobileCarWashWeb.PrivacyLiveTest do
  use MobileCarWashWeb.ConnCase

  import Phoenix.LiveViewTest

  test "GET /privacy renders the privacy policy", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/privacy")

    assert html =~ "Privacy Policy"
    assert html =~ "Driveway Detail Co"
  end

  test "discloses analytics, payment, and SMS processors", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/privacy")

    assert html =~ "Google Analytics"
    assert html =~ "Stripe"
    assert html =~ "Twilio"
  end

  test "lists a contact email and effective date", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/privacy")

    assert html =~ "hello@drivewaydetailcosa.com"
    assert html =~ "Effective"
  end

  test "landing page footer links to /privacy", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ ~s(href="/privacy")
  end
end
