defmodule MobileCarWash.Analytics.UserAgent do
  @moduledoc """
  Minimal dependency-free User-Agent parser. Buckets the requesting
  client into device_type / os / browser so persona queries can say
  "of my new customers, 62% come in on mobile iOS Safari."

  Not a full UA-parsing library — good enough for aggregation, not
  for fingerprinting.
  """

  @unknown %{device_type: :unknown, os: "Unknown", browser: "Unknown"}

  @spec parse(String.t() | nil) :: %{
          device_type: :mobile | :tablet | :desktop | :bot | :unknown,
          os: String.t(),
          browser: String.t()
        }
  def parse(nil), do: @unknown
  def parse(""), do: @unknown

  def parse(ua) when is_binary(ua) do
    %{
      device_type: device_type(ua),
      os: os(ua),
      browser: browser(ua)
    }
  end

  def parse(_), do: @unknown

  # --- Private ---

  # iPad identifies itself as mobile-ish but should bucket as tablet
  # for persona purposes.
  defp device_type(ua) do
    cond do
      ua =~ ~r/bot|crawler|spider|slurp/i -> :bot
      ua =~ ~r/iPad|Tablet|Nexus (?:7|9|10)/i -> :tablet
      ua =~ ~r/Android(?!.*Mobile)/ -> :tablet
      ua =~ ~r/iPhone|Mobile|Android|BlackBerry|webOS/ -> :mobile
      ua =~ ~r/Macintosh|Windows|Linux|CrOS/ -> :desktop
      true -> :unknown
    end
  end

  defp os(ua) do
    cond do
      ua =~ ~r/iPhone|iPad|iPod|iOS/ -> "iOS"
      ua =~ ~r/Android/ -> "Android"
      ua =~ ~r/Mac OS X|Macintosh/ -> "macOS"
      ua =~ ~r/Windows/ -> "Windows"
      ua =~ ~r/CrOS/ -> "ChromeOS"
      ua =~ ~r/Linux/ -> "Linux"
      true -> "Unknown"
    end
  end

  # Order matters — Chrome contains "Safari" in its UA, and Edge
  # contains "Chrome". Check the most specific first.
  defp browser(ua) do
    cond do
      ua =~ ~r/Edg\// -> "Edge"
      ua =~ ~r/OPR\/|Opera/ -> "Opera"
      ua =~ ~r/Firefox/ -> "Firefox"
      ua =~ ~r/Chrome/ -> "Chrome"
      ua =~ ~r/Safari/ -> "Safari"
      true -> "Unknown"
    end
  end
end
