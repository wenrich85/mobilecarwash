defmodule MobileCarWashWeb.CookieConsentController do
  @moduledoc """
  Records the visitor's cookie-consent choice from the banner.

  Expects one of three `choice` values:
    * "accept_all"      — analytics + marketing both on
    * "essential_only"  — analytics + marketing both off
    * "custom"          — respect per-category "analytics" / "marketing"
                          form flags ("true"/"false")

  The Phoenix session cookie itself and the cookie-consent row storage
  are both essential — no prior consent required to record the choice.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Analytics.CookieConsent

  def create(conn, params) do
    session_id = get_session(conn, :session_id) || fresh_session_id()
    ip_hash = hash_ip(conn.remote_ip)
    {analytics, marketing} = decode_choice(params)

    customer_id =
      case conn.assigns[:current_user] || conn.assigns[:current_customer] do
        %{id: id} -> id
        _ -> nil
      end

    _ =
      CookieConsent
      |> Ash.Changeset.for_create(:record, %{
        session_id: session_id,
        analytics: analytics,
        marketing: marketing,
        source: "banner",
        ip_hash: ip_hash,
        customer_id: customer_id
      })
      |> Ash.create(authorize?: false)

    conn
    |> put_session(:session_id, session_id)
    |> redirect(to: redirect_back(conn))
  end

  # --- Private ---

  defp decode_choice(%{"choice" => "accept_all"}), do: {true, true}
  defp decode_choice(%{"choice" => "essential_only"}), do: {false, false}

  defp decode_choice(%{"choice" => "custom"} = p) do
    {bool(p["analytics"]), bool(p["marketing"])}
  end

  defp decode_choice(_), do: {false, false}

  defp bool("true"), do: true
  defp bool(true), do: true
  defp bool(_), do: false

  defp hash_ip(ip) do
    ip
    |> :inet.ntoa()
    |> to_string()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp fresh_session_id, do: "sess_" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

  defp redirect_back(conn) do
    case get_req_header(conn, "referer") do
      [referer | _] ->
        uri = URI.parse(referer)

        if uri.host in [nil, conn.host] do
          uri.path || "/"
        else
          "/"
        end

      _ ->
        "/"
    end
  end
end
