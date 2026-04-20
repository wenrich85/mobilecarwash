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

  describe "to_e164/1" do
    test "leaves an already-E.164 number alone" do
      assert TwilioClient.to_e164("+15125551234") == "+15125551234"
    end

    test "prepends +1 to a 10-digit US number" do
      assert TwilioClient.to_e164("5125551234") == "+15125551234"
    end

    test "prepends + to an 11-digit number starting with 1" do
      assert TwilioClient.to_e164("15125551234") == "+15125551234"
    end

    test "strips dashes / parens / spaces before formatting" do
      assert TwilioClient.to_e164("(512) 555-1234") == "+15125551234"
      assert TwilioClient.to_e164("512-555-1234") == "+15125551234"
      assert TwilioClient.to_e164("512 555 1234") == "+15125551234"
    end

    test "returns nil for strings that can't be made into a plausible US number" do
      assert TwilioClient.to_e164(nil) == nil
      assert TwilioClient.to_e164("") == nil
      assert TwilioClient.to_e164("abc") == nil
      # 9 digits is not valid in US
      assert TwilioClient.to_e164("512555123") == nil
    end
  end
end
