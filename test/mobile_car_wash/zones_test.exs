defmodule MobileCarWash.ZonesTest do
  use ExUnit.Case, async: true

  alias MobileCarWash.Zones

  describe "zone_for_zip/1" do
    test "maps NW zip codes" do
      assert Zones.zone_for_zip("78249") == :nw
      assert Zones.zone_for_zip("78253") == :nw
      assert Zones.zone_for_zip("78230") == :nw
    end

    test "maps NE zip codes" do
      assert Zones.zone_for_zip("78209") == :ne
      assert Zones.zone_for_zip("78258") == :ne
      assert Zones.zone_for_zip("78217") == :ne
    end

    test "maps SW zip codes" do
      assert Zones.zone_for_zip("78211") == :sw
      assert Zones.zone_for_zip("78227") == :sw
      assert Zones.zone_for_zip("78245") == :sw
    end

    test "maps SE zip codes" do
      assert Zones.zone_for_zip("78220") == :se
      assert Zones.zone_for_zip("78223") == :se
      assert Zones.zone_for_zip("78214") == :se
    end

    test "returns nil for non-SA zip" do
      assert Zones.zone_for_zip("90210") == nil
      assert Zones.zone_for_zip("73301") == nil
    end

    test "handles zip+4 format" do
      assert Zones.zone_for_zip("78249-1234") == :nw
    end

    test "handles nil" do
      assert Zones.zone_for_zip(nil) == nil
    end
  end

  describe "zone_for_coordinates/2" do
    test "NW: north and west of center" do
      assert Zones.zone_for_coordinates(29.55, -98.60) == :nw
    end

    test "NE: north and east of center" do
      assert Zones.zone_for_coordinates(29.55, -98.40) == :ne
    end

    test "SW: south and west of center" do
      assert Zones.zone_for_coordinates(29.35, -98.60) == :sw
    end

    test "SE: south and east of center" do
      assert Zones.zone_for_coordinates(29.35, -98.40) == :se
    end
  end

  describe "serviced_zip?/1" do
    test "true for SA zips" do
      assert Zones.serviced_zip?("78249")
      assert Zones.serviced_zip?("78220")
    end

    test "false for non-SA zips" do
      refute Zones.serviced_zip?("90210")
    end
  end

  describe "display helpers" do
    test "label/1" do
      assert Zones.label(:nw) == "Northwest"
      assert Zones.label(:se) == "Southeast"
    end

    test "short_label/1" do
      assert Zones.short_label(:nw) == "NW"
      assert Zones.short_label(:se) == "SE"
    end

    test "all/0 returns 4 zones" do
      assert length(Zones.all()) == 4
    end
  end
end
