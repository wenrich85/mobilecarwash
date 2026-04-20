defmodule MobileCarWash.Analytics.EventEnrichmentTest do
  @moduledoc """
  Marketing Phase 2A / Slice 3: events now carry device metadata
  (device_type, os, browser, user_agent, page_path) and respect
  consent category gating.

  Pinned behavior:
    * :track action accepts the new metadata fields
    * Analytics.track_event/1 is a thin wrapper that:
        - auto-parses the UA string into device_type/os/browser
        - gates on category: :essential always fires; :analytics and
          :marketing fire only when the session has consented
        - returns :ok on success, :dropped_no_consent on silent skip
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Analytics
  alias MobileCarWash.Analytics.{CookieConsent, Event}

  require Ash.Query

  describe "Event :track action with metadata" do
    test "persists device_type / os / browser / page_path" do
      {:ok, event} =
        Event
        |> Ash.Changeset.for_create(:track, %{
          session_id: "sess_meta",
          event_name: "page.viewed",
          source: "web",
          properties: %{},
          device_type: :mobile,
          os: "iOS",
          browser: "Safari",
          user_agent: "Mozilla/5.0 (iPhone...)",
          page_path: "/book"
        })
        |> Ash.create()

      assert event.device_type == :mobile
      assert event.os == "iOS"
      assert event.browser == "Safari"
      assert event.page_path == "/book"
    end
  end

  describe "Analytics.track_event/1 gating" do
    test "always fires :essential events even without consent" do
      assert :ok =
               Analytics.track_event(%{
                 session_id: "sess_e_essential",
                 event_name: "booking.completed",
                 category: :essential
               })

      count =
        Event
        |> Ash.Query.filter(session_id == "sess_e_essential")
        |> Ash.read!(authorize?: false)
        |> length()

      assert count == 1
    end

    test "drops :analytics events when no consent row exists" do
      assert :dropped_no_consent =
               Analytics.track_event(%{
                 session_id: "sess_e_noconsent",
                 event_name: "page.viewed",
                 category: :analytics
               })

      events =
        Event
        |> Ash.Query.filter(session_id == "sess_e_noconsent")
        |> Ash.read!(authorize?: false)

      assert events == []
    end

    test "fires :analytics events after analytics consent is recorded" do
      sid = "sess_e_consented"

      {:ok, _} =
        CookieConsent
        |> Ash.Changeset.for_create(:record, %{
          session_id: sid,
          analytics: true,
          marketing: false
        })
        |> Ash.create(authorize?: false)

      assert :ok =
               Analytics.track_event(%{
                 session_id: sid,
                 event_name: "page.viewed",
                 category: :analytics
               })

      count =
        Event
        |> Ash.Query.filter(session_id == ^sid)
        |> Ash.read!(authorize?: false)
        |> length()

      assert count == 1
    end

    test "drops :marketing events when only analytics consented" do
      sid = "sess_e_nomarket"

      {:ok, _} =
        CookieConsent
        |> Ash.Changeset.for_create(:record, %{
          session_id: sid,
          analytics: true,
          marketing: false
        })
        |> Ash.create(authorize?: false)

      assert :dropped_no_consent =
               Analytics.track_event(%{
                 session_id: sid,
                 event_name: "retargeting.pixel_fired",
                 category: :marketing
               })
    end

    test "auto-parses user_agent into device_type/os/browser fields" do
      sid = "sess_e_ua"

      {:ok, _} =
        CookieConsent
        |> Ash.Changeset.for_create(:record, %{
          session_id: sid,
          analytics: true,
          marketing: true
        })
        |> Ash.create(authorize?: false)

      :ok =
        Analytics.track_event(%{
          session_id: sid,
          event_name: "page.viewed",
          category: :analytics,
          user_agent:
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 Version/17.4 Mobile/15E148 Safari/604.1",
          page_path: "/"
        })

      [event] =
        Event
        |> Ash.Query.filter(session_id == ^sid)
        |> Ash.read!(authorize?: false)

      assert event.device_type == :mobile
      assert event.os == "iOS"
      assert event.browser == "Safari"
    end
  end
end
