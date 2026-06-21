defmodule MobileCarWash.Notifications.EmailBlockScheduledWorkerTest do
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Notifications.Email

  test "block_scheduled/4 builds an email to the customer" do
    appt = %{
      id: "appt-1",
      scheduled_at: ~U[2026-07-01 15:00:00Z],
      price_cents: 5_000,
      duration_minutes: 45
    }

    service = %{name: "Basic Wash"}
    customer = %{name: "Sam", email: "sam@example.com"}
    address = %{street: "1 A St", city: "San Antonio", state: "TX", zip: "78261"}

    email = Email.block_scheduled(appt, service, customer, address)
    assert {"Sam", "sam@example.com"} in email.to
    assert String.downcase(email.subject) =~ "confirmed"
  end
end
