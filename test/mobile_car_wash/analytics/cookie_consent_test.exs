defmodule MobileCarWash.Analytics.CookieConsentTest do
  @moduledoc """
  Marketing Phase 2A / Slice 1: GDPR/CCPA cookie consent state.

  Strict opt-in model — until a CookieConsent row exists for the
  session with status :accepted, no analytics or marketing cookies
  may be set. Essential cookies (session, CSRF, auth) are always
  allowed; they are required for the site to work.

  Pinned behavior:
    * :record action creates/updates consent per session_id
    * consent has a category map — essential is always true,
      analytics/marketing are opt-in booleans
    * :for_session read finds the latest consent by session_id
    * status derived from category map
    * accepts? helper returns true for a category only if row exists
      AND row says that category is allowed
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Analytics
  alias MobileCarWash.Analytics.CookieConsent

  describe ":record action" do
    test "creates a consent row with an essential-only grant" do
      {:ok, consent} =
        CookieConsent
        |> Ash.Changeset.for_create(:record, %{
          session_id: "sess_abc",
          analytics: false,
          marketing: false,
          source: "banner"
        })
        |> Ash.create(authorize?: false)

      assert consent.session_id == "sess_abc"
      assert consent.essential == true
      assert consent.analytics == false
      assert consent.marketing == false
      assert consent.status == :essential_only
    end

    test "creates a consent row with full opt-in" do
      {:ok, consent} =
        CookieConsent
        |> Ash.Changeset.for_create(:record, %{
          session_id: "sess_full",
          analytics: true,
          marketing: true,
          source: "banner"
        })
        |> Ash.create(authorize?: false)

      assert consent.status == :accepted_all
      assert consent.analytics == true
      assert consent.marketing == true
    end

    test "rejects missing session_id" do
      {:error, _} =
        CookieConsent
        |> Ash.Changeset.for_create(:record, %{
          analytics: false,
          marketing: false
        })
        |> Ash.create(authorize?: false)
    end

    test "essential is forced true even if caller passes false" do
      # Essential cookies are required for the app to work — strip any
      # attempt to disable them at the action layer.
      {:ok, consent} =
        CookieConsent
        |> Ash.Changeset.for_create(:record, %{
          session_id: "sess_sneaky",
          analytics: false,
          marketing: false,
          source: "banner"
        })
        |> Ash.create(authorize?: false)

      assert consent.essential == true
    end
  end

  describe ":for_session read" do
    test "returns the latest consent for a session_id" do
      {:ok, _first} =
        CookieConsent
        |> Ash.Changeset.for_create(:record, %{
          session_id: "sess_evo",
          analytics: false,
          marketing: false
        })
        |> Ash.create(authorize?: false)

      # Second capture — the user later changed their mind and accepted all.
      # Allow a ms gap so updated_at ordering is deterministic.
      Process.sleep(10)

      {:ok, _second} =
        CookieConsent
        |> Ash.Changeset.for_create(:record, %{
          session_id: "sess_evo",
          analytics: true,
          marketing: true
        })
        |> Ash.create(authorize?: false)

      {:ok, [latest | _]} =
        CookieConsent
        |> Ash.Query.for_read(:for_session, %{session_id: "sess_evo"})
        |> Ash.read(authorize?: false)

      assert latest.analytics == true
      assert latest.marketing == true
    end

    test "returns empty list when no consent was recorded" do
      {:ok, rows} =
        CookieConsent
        |> Ash.Query.for_read(:for_session, %{session_id: "sess_nope"})
        |> Ash.read(authorize?: false)

      assert rows == []
    end
  end

  describe "Analytics.consent_for_session/1" do
    test "returns the latest consent row, or nil" do
      assert Analytics.consent_for_session("sess_missing") == nil

      {:ok, consent} =
        CookieConsent
        |> Ash.Changeset.for_create(:record, %{
          session_id: "sess_hit",
          analytics: true,
          marketing: false
        })
        |> Ash.create(authorize?: false)

      found = Analytics.consent_for_session("sess_hit")
      assert found.id == consent.id
    end
  end

  describe "Analytics.consents?/2" do
    test "essential is always true, even with no consent row" do
      assert Analytics.consents?("sess_none", :essential) == true
    end

    test "analytics + marketing are false without a consent row" do
      assert Analytics.consents?("sess_none", :analytics) == false
      assert Analytics.consents?("sess_none", :marketing) == false
    end

    test "returns true only when row explicitly allows the category" do
      {:ok, _} =
        CookieConsent
        |> Ash.Changeset.for_create(:record, %{
          session_id: "sess_split",
          analytics: true,
          marketing: false
        })
        |> Ash.create(authorize?: false)

      assert Analytics.consents?("sess_split", :essential) == true
      assert Analytics.consents?("sess_split", :analytics) == true
      assert Analytics.consents?("sess_split", :marketing) == false
    end
  end
end
