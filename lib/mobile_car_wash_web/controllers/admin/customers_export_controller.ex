defmodule MobileCarWashWeb.Admin.CustomersExportController do
  @moduledoc """
  Streams the filtered admin customer list as an RFC 4180 CSV.

  Query params mirror `/admin/customers` exactly — channel, role,
  verified, tag, q — so admins can "apply filters, Export CSV" and
  get the same cohort they're looking at.

  Pagination is deliberately ignored: the download is the full
  filtered set, not just the current page.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Marketing.{AcquisitionChannel, Tag}
  alias MobileCarWash.Reporting.CustomerList

  require Ash.Query

  @headers ~w(name email phone role channel tags last_wash_at lifetime_revenue_cents joined_at)

  def show(conn, params) do
    filters = %{
      q: Map.get(params, "q", ""),
      channel_id: Map.get(params, "channel", ""),
      role: Map.get(params, "role", ""),
      verified: Map.get(params, "verified", ""),
      tag_id: Map.get(params, "tag", "")
    }

    customers =
      filters
      |> CustomerList.list_filtered()
      |> CustomerList.sort(Map.get(params, "sort", "joined_desc"))

    channels =
      AcquisitionChannel
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.id, &1.display_name})

    tag_names =
      Tag
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.id, &1.name})

    csv = build_csv(customers, channels, tag_names)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="customers.csv"))
    |> send_resp(200, csv)
  end

  defp build_csv(customers, channels, tag_names) do
    rows =
      Enum.map(customers, fn c ->
        [
          c.name,
          to_string(c.email),
          c.phone || "",
          to_string(c.role),
          Map.get(channels, c.acquired_channel_id, ""),
          c.__tag_ids__
          |> Enum.map(&Map.get(tag_names, &1, ""))
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("|"),
          format_datetime(c.__last_wash_at__),
          Integer.to_string(c.__lifetime_revenue__ || 0),
          format_datetime(c.inserted_at)
        ]
      end)

    [@headers | rows]
    |> Enum.map(&encode_row/1)
    |> Enum.join("\r\n")
    |> Kernel.<>("\r\n")
  end

  defp encode_row(cells) do
    cells
    |> Enum.map(&encode_cell/1)
    |> Enum.join(",")
  end

  # RFC 4180: if a cell contains commas, quotes, CR, or LF, wrap the
  # whole thing in double-quotes and double any internal quotes.
  defp encode_cell(nil), do: ""
  defp encode_cell(value) when is_integer(value), do: Integer.to_string(value)

  defp encode_cell(value) do
    s = to_string(value)

    if String.contains?(s, [",", "\"", "\r", "\n"]) do
      escaped = String.replace(s, "\"", "\"\"")
      "\"" <> escaped <> "\""
    else
      s
    end
  end

  defp format_datetime(nil), do: ""
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
end
