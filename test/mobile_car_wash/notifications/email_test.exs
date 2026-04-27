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
      assert email.html_body =~ "Payment received"
      assert email.html_body =~ "John Doe"
      assert email.html_body =~ "Basic Wash"
      assert email.text_body =~ "Payment received"
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
      assert email.html_body =~ "View details"
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

      assert email.html_body =~ "drivewaydetailcosa.com/book"
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

      assert email.html_body =~ "drivewaydetailcosa.com/subscribe"
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

  # ---------------------------------------------------------------------------
  # Per-email smoke tests — assert subject, from, and Layout wrapping (footer
  # present in both html and text). Covers all 11 functions plus
  # booking_cancelled with/without reason.
  # ---------------------------------------------------------------------------

  defp smoke_customer, do: %{name: "Maria", email: "maria@example.com"}

  defp smoke_plan,
    do: %{
      name: "Monthly Premium",
      price_cents: 7_900,
      basic_washes_per_month: 2,
      deep_cleans_per_month: 1,
      deep_clean_discount_percent: 10
    }

  defp smoke_service_type, do: %{name: "Premium Wash"}

  defp smoke_appointment do
    %{
      scheduled_at: ~U[2026-04-28 10:00:00Z],
      completed_at: nil,
      duration_minutes: 75,
      price_cents: 9_999,
      id: "appt_test123",
      cancellation_reason: nil
    }
  end

  defp smoke_payment,
    do: %{id: "py_test123", amount_cents: 9_999, paid_at: ~U[2026-04-28 11:30:00Z]}

  defp smoke_address,
    do: %{street: "123 Main St", city: "San Antonio", state: "TX", zip: "78261"}

  defp smoke_task,
    do: %{
      name: "Renew LLC filing",
      due_date: ~U[2026-05-01 00:00:00Z],
      priority: "high",
      status: "pending",
      description: "Annual renewal",
      external_url: "https://comptroller.texas.gov"
    }

  defp smoke_category, do: %{name: "Legal"}

  defp assert_branded_email(email, expected_subject_substr) do
    assert email.subject =~ expected_subject_substr
    assert email.from == {"Driveway Detail Co", "noreply@drivewaydetailcosa.com"}
    assert email.html_body =~ "Driveway Detail Co. LLC"
    assert email.text_body =~ "Driveway Detail Co. LLC"
  end

  describe "smoke: verify_email/2" do
    test "wraps with Layout and sets correct subject" do
      email = Email.verify_email(smoke_customer(), "https://example.com/verify/abc")
      assert_branded_email(email, "Verify your email")
      assert email.html_body =~ "https://example.com/verify/abc"
    end
  end

  describe "smoke: booking_confirmation/4" do
    test "wraps with Layout" do
      email =
        Email.booking_confirmation(
          smoke_appointment(),
          smoke_service_type(),
          smoke_customer(),
          smoke_address()
        )

      assert_branded_email(email, "Booking Confirmed")
      assert email.html_body =~ "Premium Wash"
      assert email.html_body =~ "123 Main St"
      assert email.html_body =~ "75 minutes"
      assert email.html_body =~ "appt_test123"
    end
  end

  describe "smoke: appointment_reminder/4" do
    test "wraps with Layout" do
      email =
        Email.appointment_reminder(
          smoke_appointment(),
          smoke_service_type(),
          smoke_customer(),
          smoke_address()
        )

      assert_branded_email(email, "Reminder")
      assert email.html_body =~ "123 Main St"
    end
  end

  describe "smoke: deadline_reminder/4" do
    test "wraps with Layout" do
      email =
        Email.deadline_reminder(
          smoke_task(),
          smoke_category(),
          3,
          "admin@drivewaydetailcosa.com"
        )

      assert email.subject =~ "Renew LLC filing"
      assert email.from == {"Driveway Detail Co", "noreply@drivewaydetailcosa.com"}
      assert email.html_body =~ "Driveway Detail Co. LLC"
      assert email.html_body =~ "high"
      assert email.html_body =~ "Legal"
    end
  end

  describe "smoke: payment_receipt/3" do
    test "wraps with Layout and shows formatted amount" do
      email = Email.payment_receipt(smoke_customer(), smoke_payment(), "Premium Wash")
      assert_branded_email(email, "Payment Receipt")
      assert email.subject =~ "$99.99"
      assert email.html_body =~ "$99.99"
      assert email.html_body =~ "py_test123"
    end
  end

  describe "smoke: wash_completed/3" do
    test "wraps with Layout" do
      email = Email.wash_completed(smoke_customer(), smoke_appointment(), "Premium Wash")
      assert_branded_email(email, "Complete")
      assert email.html_body =~ "appt_test123"
    end
  end

  describe "smoke: tech_on_the_way/4" do
    test "wraps with Layout" do
      email =
        Email.tech_on_the_way(smoke_customer(), smoke_appointment(), "Premium Wash", "Jordan")

      assert_branded_email(email, "tech is on the way")
      assert email.html_body =~ "Jordan"
    end
  end

  describe "smoke: tech_arrived/4" do
    test "wraps with Layout" do
      email =
        Email.tech_arrived(smoke_customer(), smoke_appointment(), "Premium Wash", "Jordan")

      assert_branded_email(email, "tech has arrived")
      assert email.html_body =~ "Jordan"
    end
  end

  describe "smoke: booking_cancelled/3" do
    test "with reason wraps with Layout and shows reason" do
      appt_with_reason = %{smoke_appointment() | cancellation_reason: "Weather"}
      email = Email.booking_cancelled(smoke_customer(), appt_with_reason, "Premium Wash")
      assert_branded_email(email, "Booking Cancelled")
      assert email.html_body =~ "Weather"
      assert email.text_body =~ "Reason: Weather"
    end

    test "without reason omits reason block" do
      email = Email.booking_cancelled(smoke_customer(), smoke_appointment(), "Premium Wash")
      assert_branded_email(email, "Booking Cancelled")
      refute email.html_body =~ "Reason:"
    end
  end

  describe "smoke: subscription_created/2" do
    test "wraps with Layout" do
      email = Email.subscription_created(smoke_customer(), smoke_plan())
      assert_branded_email(email, "Welcome to Monthly Premium")
      assert email.html_body =~ "$79/month"
      assert email.html_body =~ "2 basic washes per month"
      assert email.html_body =~ "1 deep clean per month"
    end
  end

  describe "smoke: subscription_cancelled/2" do
    test "wraps with Layout" do
      email = Email.subscription_cancelled(smoke_customer(), smoke_plan())
      assert_branded_email(email, "Subscription Has Been Cancelled")
    end
  end
end
