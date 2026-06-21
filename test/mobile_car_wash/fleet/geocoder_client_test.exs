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
end
