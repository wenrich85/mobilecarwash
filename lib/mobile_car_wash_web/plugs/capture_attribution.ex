defmodule MobileCarWashWeb.Plugs.CaptureAttribution do
  @moduledoc """
  First-touch attribution capture. Reads UTM params + `?ref=CODE` +
  the Referer header off the inbound request and stashes them in the
  session as a single `:attribution` map.

  Never overwrites an existing attribution map — first-touch wins.
  Rationale: for a solo operator starting paid marketing, "who
  originally found this customer" is the signal worth optimizing.
  Last-touch over-credits retargeting + branded search.

  Stored shape (string keys, so it survives the session encoder):

      %{
        "utm_source"    => "meta",
        "utm_medium"    => "cpc",
        "utm_campaign"  => "spring_2026",
        "utm_content"   => "ad_a",
        "referrer"      => "https://facebook.com/",
        "referred_by_id" => "<uuid or nil>",
        "first_touch_at" => "2026-04-19T12:00:00Z"
      }

  Downstream consumers:
    * LiveAuth :hydrate_attribution hook lifts this into socket assigns.
    * BookingLive / AuthController pass these as args to
      `register_with_password` / `create_guest`.
  """
  @behaviour Plug

  import Plug.Conn

  alias MobileCarWash.Accounts.Customer

  require Ash.Query

  @utm_keys ~w(utm_source utm_medium utm_campaign utm_content)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case get_session(conn, :attribution) do
      %{} ->
        # First-touch already captured — preserve it verbatim.
        conn

      _ ->
        maybe_capture(conn)
    end
  end

  defp maybe_capture(conn) do
    # conn.params can be %Plug.Conn.Unfetched{} when no parser has run
    # yet (e.g. static-file requests). Fall back to fetching query
    # params directly so we never crash inert traffic.
    params =
      case conn.params do
        %Plug.Conn.Unfetched{} ->
          fetch_query_params(conn).query_params || %{}

        %{} = p ->
          p

        _ ->
          %{}
      end

    utm = Map.take(params, @utm_keys)
    ref = params["ref"]
    referer = conn |> get_req_header("referer") |> List.first()

    if utm == %{} and is_nil(ref) and is_nil(referer) do
      # Nothing worth capturing — stay silent so /admin and other
      # non-marketing traffic doesn't pollute sessions.
      conn
    else
      attribution =
        utm
        |> Map.put("referrer", referer)
        |> Map.put("referred_by_id", resolve_referred_by_id(ref))
        |> Map.put("first_touch_at", DateTime.utc_now() |> DateTime.to_iso8601())
        |> drop_nils()

      put_session(conn, :attribution, attribution)
    end
  end

  defp resolve_referred_by_id(nil), do: nil
  defp resolve_referred_by_id(""), do: nil

  defp resolve_referred_by_id(code) when is_binary(code) do
    case Customer
         |> Ash.Query.for_read(:by_referral_code, %{referral_code: code})
         |> Ash.read(authorize?: false) do
      {:ok, [customer | _]} -> customer.id
      _ -> nil
    end
  end

  defp drop_nils(map), do: :maps.filter(fn _k, v -> not is_nil(v) end, map)
end
