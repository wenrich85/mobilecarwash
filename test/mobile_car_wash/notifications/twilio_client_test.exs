defmodule MobileCarWash.Notifications.TwilioClientTest do
  use ExUnit.Case, async: false

  alias MobileCarWash.Notifications.TwilioClient
  alias MobileCarWash.Notifications.TwilioClientMock

  describe "send_sms/2" do
    test "delegates to configured client module" do
      TwilioClientMock.init()

      assert {:ok, "SM_mock_" <> _} = TwilioClient.send_sms("+15125551234", "Test message")
      assert [{"+15125551234", "Test message"}] = TwilioClientMock.messages()
    end

    test "returns {:error, :sms_not_configured} when Twilio credentials missing" do
      original = Application.get_env(:mobile_car_wash, :twilio)
      original_client = Application.get_env(:mobile_car_wash, :twilio_client)
      Application.put_env(:mobile_car_wash, :twilio, nil)
      Application.delete_env(:mobile_car_wash, :twilio_client)

      assert {:error, :sms_not_configured} = TwilioClient.send_sms("+15125551234", "Test")

      if original, do: Application.put_env(:mobile_car_wash, :twilio, original)

      if original_client,
        do: Application.put_env(:mobile_car_wash, :twilio_client, original_client)
    end
  end
end
