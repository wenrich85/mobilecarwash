defmodule MobileCarWash.Fleet.GeocoderClientTest do
  use ExUnit.Case, async: false

  alias MobileCarWash.Fleet.GeocoderClient
  alias MobileCarWash.Fleet.GeocoderClientMock

  setup do
    GeocoderClientMock.init()
    :ok
  end

  test "suggest/1 delegates to the configured mock and returns staged matches" do
    staged = [
      %{
        label: "123 MAIN ST, SAN ANTONIO, TX, 78261",
        street: "123 MAIN ST",
        city: "SAN ANTONIO",
        state: "TX",
        zip: "78261",
        lat: 29.65,
        lng: -98.42
      }
    ]

    GeocoderClientMock.put_suggestions("123 main", staged)

    assert {:ok, ^staged} = GeocoderClient.suggest("123 main")
  end

  test "suggest/1 returns {:ok, []} for an unstaged query" do
    assert {:ok, []} = GeocoderClient.suggest("nothing staged here")
  end

  test "suggest/1 surfaces staged errors" do
    GeocoderClientMock.put_error("boom", :timeout)
    assert {:error, :timeout} = GeocoderClient.suggest("boom")
  end

  describe "filter_to_service_area/1" do
    test "keeps suggestions whose ZIP is in the service area and drops the rest" do
      suggestions = [
        %{
          label: "1 A St",
          street: "1 A St",
          city: "San Antonio",
          state: "TX",
          zip: "78261",
          lat: 29.6,
          lng: -98.42
        },
        %{
          label: "2 B St",
          street: "2 B St",
          city: "Austin",
          state: "TX",
          zip: "73301",
          lat: 30.27,
          lng: -97.74
        },
        %{label: "3 C St", street: "3 C St", city: "", state: "", zip: "", lat: 0.0, lng: 0.0}
      ]

      assert [%{zip: "78261"}] = GeocoderClient.filter_to_service_area(suggestions)
    end

    test "returns [] when no suggestion is in the service area" do
      assert [] =
               GeocoderClient.filter_to_service_area([
                 %{
                   label: "x",
                   street: "x",
                   city: "Austin",
                   state: "TX",
                   zip: "73301",
                   lat: 30.27,
                   lng: -97.74
                 }
               ])
    end
  end

  describe "census_query/1" do
    test "appends the service region to a bare street query" do
      assert GeocoderClient.census_query("123 Main St") == "123 Main St, San Antonio, TX"
    end

    test "leaves a query that already contains a comma untouched" do
      assert GeocoderClient.census_query("123 Main St, Boerne, TX") == "123 Main St, Boerne, TX"
    end
  end
end
