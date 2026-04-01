defmodule MobileCarWash.Notifications.EmailTest do
  use ExUnit.Case, async: true

  alias MobileCarWash.Notifications.Email

  describe "payment_receipt/3" do
    test "returns a valid email with correct structure" do
      customer = %{name: "John Doe", email: "john@example.com"}
      payment = %{id: "pay_123", amount_cents: 5_000, paid_at: DateTime.utc_now()}
      service_name = "Basic Wash"

      email = Email.payment_receipt(customer, payment, service_name)

      assert email.__struct__ == Swoosh.Email
      assert email.to == [{"John Doe", "john@example.com"}]
      assert email.subject =~ "Payment Receipt"
      assert email.subject =~ "50"
      assert email.html_body =~ "Payment Receipt"
      assert email.html_body =~ "John Doe"
      assert email.html_body =~ "Basic Wash"
      assert email.text_body =~ "Payment Receipt"
    end

    test "formats amount correctly in dollars" do
      customer = %{name: "Test", email: "test@example.com"}
      payment = %{id: "pay_123", amount_cents: 12_345, paid_at: DateTime.utc_now()}
      service_name = "Premium Detail"

      email = Email.payment_receipt(customer, payment, service_name)

      assert email.html_body =~ "123.45"
    end

    test "includes branding footer" do
      customer = %{name: "Test", email: "test@example.com"}
      payment = %{id: "pay_123", amount_cents: 5_000, paid_at: DateTime.utc_now()}
      service_name = "Test Service"

      email = Email.payment_receipt(customer, payment, service_name)

      assert email.html_body =~ "Driveway Detail Co"
      assert email.html_body =~ "San Antonio, TX"
      assert email.html_body =~ "Veteran-owned"
    end
  end

  describe "wash_completed/3" do
    test "returns a valid email with correct structure" do
      customer = %{name: "Jane Doe", email: "jane@example.com"}
      appointment = %{
        id: "apt_123",
        scheduled_at: DateTime.new!(~D[2026-04-15], ~T[10:00:00])
      }
      service_name = "Deep Clean"

      email = Email.wash_completed(customer, appointment, service_name)

      assert email.__struct__ == Swoosh.Email
      assert email.to == [{"Jane Doe", "jane@example.com"}]
      assert email.subject =~ "Complete"
      assert email.html_body =~ "Your wash is complete"
      assert email.html_body =~ "Jane Doe"
      assert email.html_body =~ "Deep Clean"
      assert email.text_body =~ "complete"
    end

    test "includes appointment view link" do
      customer = %{name: "Test", email: "test@example.com"}
      appointment = %{
        id: "apt_456",
        scheduled_at: DateTime.new!(~D[2026-04-15], ~T[10:00:00])
      }
      service_name = "Test"

      email = Email.wash_completed(customer, appointment, service_name)

      assert email.html_body =~ "apt_456"
      assert email.html_body =~ "View Details"
    end

    test "includes branding footer" do
      customer = %{name: "Test", email: "test@example.com"}
      appointment = %{
        id: "apt_123",
        scheduled_at: DateTime.new!(~D[2026-04-15], ~T[10:00:00])
      }
      service_name = "Test"

      email = Email.wash_completed(customer, appointment, service_name)

      assert email.html_body =~ "Driveway Detail Co"
    end
  end

  describe "subscription_created/2" do
    test "returns a valid email with correct structure" do
      customer = %{name: "Bob Smith", email: "bob@example.com"}
      plan = %{
        name: "Pro Plan",
        price_cents: 12_500,
        basic_washes_per_month: 4,
        deep_cleans_per_month: 1,
        deep_clean_discount_percent: 30
      }

      email = Email.subscription_created(customer, plan)

      assert email.__struct__ == Swoosh.Email
      assert email.to == [{"Bob Smith", "bob@example.com"}]
      assert email.subject =~ "Welcome"
      assert email.subject =~ "Pro Plan"
      assert email.html_body =~ "Welcome"
      assert email.html_body =~ "Pro Plan"
      assert email.html_body =~ "125"
      assert email.text_body =~ "Welcome"
    end

    test "includes plan benefits" do
      customer = %{name: "Test", email: "test@example.com"}
      plan = %{
        name: "Test Plan",
        price_cents: 9_999,
        basic_washes_per_month: 2,
        deep_cleans_per_month: 1,
        deep_clean_discount_percent: 20
      }

      email = Email.subscription_created(customer, plan)

      assert email.html_body =~ "2 basic wash"
      assert email.html_body =~ "1 deep clean"
      assert email.html_body =~ "20%"
    end

    test "includes booking link" do
      customer = %{name: "Test", email: "test@example.com"}
      plan = %{
        name: "Test",
        price_cents: 5_000,
        basic_washes_per_month: 1,
        deep_cleans_per_month: 0,
        deep_clean_discount_percent: 0
      }

      email = Email.subscription_created(customer, plan)

      assert email.html_body =~ "drivewaydetail.co/book"
    end

    test "includes branding footer" do
      customer = %{name: "Test", email: "test@example.com"}
      plan = %{
        name: "Test",
        price_cents: 5_000,
        basic_washes_per_month: 0,
        deep_cleans_per_month: 0,
        deep_clean_discount_percent: 0
      }

      email = Email.subscription_created(customer, plan)

      assert email.html_body =~ "Driveway Detail Co"
    end
  end

  describe "subscription_cancelled/2" do
    test "returns a valid email with correct structure" do
      customer = %{name: "Alice Jones", email: "alice@example.com"}
      plan = %{name: "Basic Plan", price_cents: 9_000}

      email = Email.subscription_cancelled(customer, plan)

      assert email.__struct__ == Swoosh.Email
      assert email.to == [{"Alice Jones", "alice@example.com"}]
      assert email.subject =~ "Cancelled"
      assert email.subject =~ "Basic Plan"
      assert email.html_body =~ "cancelled"
      assert email.html_body =~ "Alice Jones"
      assert email.text_body =~ "cancelled"
    end

    test "includes resubscribe link" do
      customer = %{name: "Test", email: "test@example.com"}
      plan = %{name: "Test", price_cents: 5_000}

      email = Email.subscription_cancelled(customer, plan)

      assert email.html_body =~ "drivewaydetail.co/subscribe"
      assert email.html_body =~ "resubscribe"
    end

    test "has friendly tone" do
      customer = %{name: "Test", email: "test@example.com"}
      plan = %{name: "Test", price_cents: 5_000}

      email = Email.subscription_cancelled(customer, plan)

      assert email.html_body =~ "love to have you back"
    end

    test "includes branding footer" do
      customer = %{name: "Test", email: "test@example.com"}
      plan = %{name: "Test", price_cents: 5_000}

      email = Email.subscription_cancelled(customer, plan)

      assert email.html_body =~ "Driveway Detail Co"
    end
  end
end
