defmodule MobileCarWashWeb.Plugs.CaptureAttributionTest do
  @moduledoc """
  Marketing Phase 1 / Slice 3: the CaptureAttribution plug stamps the
  *first* touch the visitor makes onto the session. Later LiveViews
  lift that map into socket assigns and pass it through to the
  register/guest-create action as attribution args.

  First-touch semantics — once a session has :attribution set, later
  visits with different UTMs must NOT overwrite it. The rationale:
  for a solo operator starting paid marketing, "who originally found
  this customer" is the signal worth optimizing; last-touch
  over-credits retargeting + branded search.
  """
  use MobileCarWashWeb.ConnCase, async: true

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Marketing
  alias MobileCarWashWeb.Plugs.CaptureAttribution

  setup do
    :ok = Marketing.seed_channels!()
    :ok
  end

  defp run_plug(conn) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> CaptureAttribution.call(CaptureAttribution.init([]))
  end

  describe "first touch" do
    test "captures UTMs from query string into session", %{conn: conn} do
      conn =
        %{conn | query_string: "utm_source=meta&utm_medium=cpc&utm_campaign=spring"}
        |> Map.put(:params, %{
          "utm_source" => "meta",
          "utm_medium" => "cpc",
          "utm_campaign" => "spring"
        })
        |> run_plug()

      attribution = Plug.Conn.get_session(conn, :attribution)
      assert attribution["utm_source"] == "meta"
      assert attribution["utm_medium"] == "cpc"
      assert attribution["utm_campaign"] == "spring"
      assert attribution["first_touch_at"] != nil
    end

    test "captures referer header", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.put_req_header("referer", "https://t.co/abc")
        |> Map.put(:params, %{"utm_source" => "x", "utm_medium" => "social"})
        |> run_plug()

      assert Plug.Conn.get_session(conn, :attribution)["referrer"] == "https://t.co/abc"
    end

    test "resolves ?ref=CODE into referred_by_id", %{conn: conn} do
      {:ok, referrer} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "ref-plug-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Plug Referrer",
          phone: "+15125550100"
        })
        |> Ash.create()

      conn = Map.put(conn, :params, %{"ref" => referrer.referral_code}) |> run_plug()

      assert Plug.Conn.get_session(conn, :attribution)["referred_by_id"] == referrer.id
    end

    test "ignores unknown referral codes gracefully", %{conn: conn} do
      conn =
        Map.put(conn, :params, %{"ref" => "NOSUCHCODE", "utm_source" => "meta"})
        |> run_plug()

      attribution = Plug.Conn.get_session(conn, :attribution)
      # UTM still captured, but referred_by_id stays nil
      assert attribution["utm_source"] == "meta"
      refute attribution["referred_by_id"]
    end
  end

  describe "first-touch preservation" do
    test "does not overwrite existing attribution on later visits", %{conn: conn} do
      # First visit
      conn =
        Map.put(conn, :params, %{"utm_source" => "google", "utm_medium" => "organic"})
        |> run_plug()

      first = Plug.Conn.get_session(conn, :attribution)
      assert first["utm_source"] == "google"

      # Simulate a subsequent visit with a DIFFERENT UTM — the plug
      # must preserve the first touch.
      conn =
        conn
        |> Map.put(:params, %{"utm_source" => "meta", "utm_medium" => "cpc"})
        |> CaptureAttribution.call(CaptureAttribution.init([]))

      second = Plug.Conn.get_session(conn, :attribution)
      assert second["utm_source"] == "google"
      assert second["utm_medium"] == "organic"
      # first_touch_at preserved
      assert second["first_touch_at"] == first["first_touch_at"]
    end
  end

  describe "no-op paths" do
    test "does nothing when no attribution params are present", %{conn: conn} do
      conn = run_plug(conn)
      refute Plug.Conn.get_session(conn, :attribution)
    end
  end
end
