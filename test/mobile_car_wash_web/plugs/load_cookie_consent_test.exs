defmodule MobileCarWashWeb.Plugs.LoadCookieConsentTest do
  @moduledoc """
  Marketing Phase 2A / Slice 2: loads the current CookieConsent row
  (if any) for the session_id into conn.assigns[:current_consent].
  The root layout uses that assign to decide whether to show the
  banner.
  """
  use MobileCarWashWeb.ConnCase, async: false

  alias MobileCarWash.Analytics.CookieConsent
  alias MobileCarWashWeb.Plugs.{EnsureSessionId, LoadCookieConsent}

  defp run_chain(conn) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> EnsureSessionId.call(EnsureSessionId.init([]))
    |> LoadCookieConsent.call(LoadCookieConsent.init([]))
  end

  test "assigns current_consent=nil when no consent recorded",
       %{conn: conn} do
    conn = run_chain(conn)

    assert conn.assigns[:current_consent] == nil
  end

  test "assigns the latest consent row for the session", %{conn: conn} do
    # Wire session_id up front so we can insert consent for it.
    sid = "sess_ctx_#{System.unique_integer([:positive])}"

    {:ok, _} =
      CookieConsent
      |> Ash.Changeset.for_create(:record, %{
        session_id: sid,
        analytics: true,
        marketing: false
      })
      |> Ash.create(authorize?: false)

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{session_id: sid})
      |> EnsureSessionId.call(EnsureSessionId.init([]))
      |> LoadCookieConsent.call(LoadCookieConsent.init([]))

    consent = conn.assigns[:current_consent]
    assert consent != nil
    assert consent.session_id == sid
    assert consent.analytics == true
  end
end
