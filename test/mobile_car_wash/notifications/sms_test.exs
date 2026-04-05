defmodule MobileCarWash.Notifications.SMSTest do
  use ExUnit.Case, async: true

  alias MobileCarWash.Notifications.SMS

  describe "booking_confirmation/3" do
    test "includes service name, date, time, and address" do
      appointment = %{scheduled_at: ~U[2026-04-15 15:00:00Z]}
      service_type = %{name: "Basic Wash"}
      address = %{street: "123 Main St", city: "San Antonio"}

      msg = SMS.booking_confirmation(appointment, service_type, address)

      assert msg =~ "Basic Wash"
      assert msg =~ "123 Main St"
      assert msg =~ "San Antonio"
      assert is_binary(msg)
    end
  end

  describe "appointment_reminder/3" do
    test "includes service name and time" do
      appointment = %{scheduled_at: ~U[2026-04-15 15:00:00Z]}
      service_type = %{name: "Deep Clean & Detail"}
      address = %{street: "456 Oak Dr", city: "Converse"}

      msg = SMS.appointment_reminder(appointment, service_type, address)

      assert msg =~ "Deep Clean & Detail"
      assert msg =~ "tomorrow"
      assert is_binary(msg)
    end
  end

  describe "tech_on_the_way/2" do
    test "includes technician name" do
      appointment = %{scheduled_at: ~U[2026-04-15 15:00:00Z]}
      technician = %{name: "Marcus Rivera"}

      msg = SMS.tech_on_the_way(appointment, technician)

      assert msg =~ "Marcus Rivera"
      assert msg =~ "on the way"
      assert is_binary(msg)
    end
  end

  describe "wash_completed/2" do
    test "includes service name" do
      appointment = %{scheduled_at: ~U[2026-04-15 15:00:00Z]}
      service_type = %{name: "Basic Wash"}

      msg = SMS.wash_completed(appointment, service_type)

      assert msg =~ "Basic Wash"
      assert msg =~ "complete"
      assert is_binary(msg)
    end
  end
end
