defmodule MobileCarWash.Routing.HaversineTest do
  @moduledoc """
  Great-circle distance + estimated travel time for the route optimizer.
  Haversine is a rough MVP; roads aren't straight lines so we apply a detour
  factor (~1.4) to approximate driving distance.
  """
  use ExUnit.Case, async: true

  alias MobileCarWash.Routing.Haversine

  describe "distance_miles/2" do
    test "returns 0 for the same point" do
      assert Haversine.distance_miles({29.65, -98.42}, {29.65, -98.42}) == 0.0
    end

    test "computes a plausible distance across San Antonio (shop to downtown)" do
      # Shop (78261) ~ {29.65, -98.42}; downtown Alamo ~ {29.4241, -98.4936}
      # Great-circle distance is roughly 16 miles.
      d = Haversine.distance_miles({29.65, -98.42}, {29.4241, -98.4936})
      assert d > 15.0 and d < 18.0
    end

    test "symmetric — order of points does not matter" do
      a = {29.65, -98.42}
      b = {29.52, -98.58}
      assert_in_delta Haversine.distance_miles(a, b), Haversine.distance_miles(b, a), 0.001
    end
  end

  describe "travel_minutes/2" do
    test "returns 0 minutes for the same point" do
      assert Haversine.travel_minutes({29.65, -98.42}, {29.65, -98.42}) == 0
    end

    test "applies detour factor and speed — ~16mi great-circle → ~44min drive at 30mph with 1.4x factor" do
      # 16mi * 1.4 detour / 30mph = 0.747 hr = 44.8 min → rounded up
      minutes = Haversine.travel_minutes({29.65, -98.42}, {29.4241, -98.4936})
      assert minutes >= 42 and minutes <= 48
    end

    test "returns an integer" do
      minutes = Haversine.travel_minutes({29.65, -98.42}, {29.52, -98.58})
      assert is_integer(minutes)
    end
  end
end
