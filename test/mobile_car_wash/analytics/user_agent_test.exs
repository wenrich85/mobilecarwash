defmodule MobileCarWash.Analytics.UserAgentTest do
  @moduledoc """
  Marketing Phase 2A / Slice 3: minimal, dependency-free UA parser.
  Good enough to bucket visitors for persona work — "mobile safari on
  ios" vs "desktop chrome on windows" is all we need, we're not
  building a browser-analytics product.
  """
  use ExUnit.Case, async: true

  alias MobileCarWash.Analytics.UserAgent

  describe "parse/1" do
    test "identifies iOS Safari" do
      ua =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 " <>
          "(KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"

      assert %{device_type: :mobile, os: "iOS", browser: "Safari"} = UserAgent.parse(ua)
    end

    test "identifies Android Chrome" do
      ua =
        "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) " <>
          "Chrome/124.0.0.0 Mobile Safari/537.36"

      assert %{device_type: :mobile, os: "Android", browser: "Chrome"} = UserAgent.parse(ua)
    end

    test "identifies Desktop Chrome on macOS" do
      ua =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " <>
          "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

      assert %{device_type: :desktop, os: "macOS", browser: "Chrome"} = UserAgent.parse(ua)
    end

    test "identifies Desktop Firefox on Windows" do
      ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0"

      assert %{device_type: :desktop, os: "Windows", browser: "Firefox"} = UserAgent.parse(ua)
    end

    test "identifies iPad as tablet" do
      ua =
        "Mozilla/5.0 (iPad; CPU OS 17_4 like Mac OS X) AppleWebKit/605.1.15 " <>
          "(KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"

      assert %{device_type: :tablet} = UserAgent.parse(ua)
    end

    test "returns :unknown fields for a gibberish UA" do
      assert %{device_type: :unknown, os: "Unknown", browser: "Unknown"} =
               UserAgent.parse("blahblah")
    end

    test "handles nil / empty safely" do
      assert %{device_type: :unknown} = UserAgent.parse(nil)
      assert %{device_type: :unknown} = UserAgent.parse("")
    end
  end
end
