defmodule MobileCarWash.Notifications.Email do
  @moduledoc """
  Email templates for the mobile car wash application.
  Uses Swoosh for email composition.
  """
  import Swoosh.Email

  @from {"Mobile Car Wash", "noreply@mobilecarwash.com"}

  @doc """
  Booking confirmation email — sent after successful payment.
  """
  def booking_confirmation(appointment, service_type, customer, address) do
    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Booking Confirmed - #{service_type.name}")
    |> html_body("""
    <h2>Your booking is confirmed!</h2>

    <p>Hi #{customer.name},</p>

    <p>Your <strong>#{service_type.name}</strong> has been scheduled. Here are the details:</p>

    <table style="border-collapse: collapse; margin: 20px 0;">
      <tr>
        <td style="padding: 8px; font-weight: bold;">Service:</td>
        <td style="padding: 8px;">#{service_type.name}</td>
      </tr>
      <tr>
        <td style="padding: 8px; font-weight: bold;">Date & Time:</td>
        <td style="padding: 8px;">#{Calendar.strftime(appointment.scheduled_at, "%B %d, %Y at %I:%M %p")}</td>
      </tr>
      <tr>
        <td style="padding: 8px; font-weight: bold;">Duration:</td>
        <td style="padding: 8px;">#{appointment.duration_minutes} minutes</td>
      </tr>
      <tr>
        <td style="padding: 8px; font-weight: bold;">Location:</td>
        <td style="padding: 8px;">#{address.street}, #{address.city}, #{address.state} #{address.zip}</td>
      </tr>
      <tr>
        <td style="padding: 8px; font-weight: bold;">Total:</td>
        <td style="padding: 8px;">$#{div(appointment.price_cents, 100)}</td>
      </tr>
    </table>

    <p>We'll be there on time. Please ensure your vehicle is accessible at the scheduled location.</p>

    <p>Booking ID: <code>#{appointment.id}</code></p>

    <p>Thank you for choosing Mobile Car Wash!</p>
    """)
    |> text_body("""
    Your booking is confirmed!

    Hi #{customer.name},

    Service: #{service_type.name}
    Date & Time: #{Calendar.strftime(appointment.scheduled_at, "%B %d, %Y at %I:%M %p")}
    Duration: #{appointment.duration_minutes} minutes
    Location: #{address.street}, #{address.city}, #{address.state} #{address.zip}
    Total: $#{div(appointment.price_cents, 100)}

    Booking ID: #{appointment.id}

    Thank you for choosing Mobile Car Wash!
    """)
  end

  @doc """
  Appointment reminder email — sent 24 hours before the appointment.
  """
  def appointment_reminder(appointment, service_type, customer, address) do
    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Reminder: #{service_type.name} Tomorrow")
    |> html_body("""
    <h2>Appointment Reminder</h2>

    <p>Hi #{customer.name},</p>

    <p>This is a friendly reminder that your <strong>#{service_type.name}</strong> is scheduled for tomorrow.</p>

    <table style="border-collapse: collapse; margin: 20px 0;">
      <tr>
        <td style="padding: 8px; font-weight: bold;">Date & Time:</td>
        <td style="padding: 8px;">#{Calendar.strftime(appointment.scheduled_at, "%B %d, %Y at %I:%M %p")}</td>
      </tr>
      <tr>
        <td style="padding: 8px; font-weight: bold;">Location:</td>
        <td style="padding: 8px;">#{address.street}, #{address.city}, #{address.state} #{address.zip}</td>
      </tr>
    </table>

    <p>Please make sure your vehicle is parked and accessible at the service location.</p>

    <p>See you tomorrow!</p>
    """)
    |> text_body("""
    Appointment Reminder

    Hi #{customer.name},

    Your #{service_type.name} is scheduled for tomorrow.

    Date & Time: #{Calendar.strftime(appointment.scheduled_at, "%B %d, %Y at %I:%M %p")}
    Location: #{address.street}, #{address.city}, #{address.state} #{address.zip}

    Please make sure your vehicle is parked and accessible.

    See you tomorrow!
    """)
  end

  @doc """
  Deadline reminder email — sent to admin for upcoming compliance/formation tasks.
  """
  def deadline_reminder(task, category, days_before, admin_email) do
    due_str = if task.due_date, do: Calendar.strftime(task.due_date, "%B %d, %Y"), else: "No date set"
    url_line = if task.external_url, do: "<p><a href=\"#{task.external_url}\">Go to website →</a></p>", else: ""

    new()
    |> to(admin_email)
    |> from(@from)
    |> subject("Deadline: #{task.name} — due in #{days_before} day(s)")
    |> html_body("""
    <h2>Compliance Deadline Reminder</h2>

    <p>The following task is due in <strong>#{days_before} day(s)</strong>:</p>

    <table style="border-collapse: collapse; margin: 20px 0;">
      <tr>
        <td style="padding: 8px; font-weight: bold;">Task:</td>
        <td style="padding: 8px;">#{task.name}</td>
      </tr>
      <tr>
        <td style="padding: 8px; font-weight: bold;">Category:</td>
        <td style="padding: 8px;">#{category.name}</td>
      </tr>
      <tr>
        <td style="padding: 8px; font-weight: bold;">Due Date:</td>
        <td style="padding: 8px;">#{due_str}</td>
      </tr>
      <tr>
        <td style="padding: 8px; font-weight: bold;">Priority:</td>
        <td style="padding: 8px;">#{task.priority}</td>
      </tr>
      <tr>
        <td style="padding: 8px; font-weight: bold;">Status:</td>
        <td style="padding: 8px;">#{task.status}</td>
      </tr>
    </table>

    #{if task.description, do: "<p><strong>Notes:</strong> #{task.description}</p>", else: ""}
    #{url_line}

    <p>Log in to your admin dashboard to update this task.</p>
    """)
    |> text_body("""
    Compliance Deadline Reminder

    Task: #{task.name}
    Category: #{category.name}
    Due Date: #{due_str}
    Priority: #{task.priority}
    Status: #{task.status}
    #{if task.description, do: "Notes: #{task.description}", else: ""}
    #{if task.external_url, do: "URL: #{task.external_url}", else: ""}

    Due in #{days_before} day(s). Log in to update.
    """)
  end

  @doc """
  Payment receipt email — sent after each successful payment.
  """
  def payment_receipt(customer, payment, service_name) do
    paid_at = if payment.paid_at, do: Calendar.strftime(payment.paid_at, "%B %d, %Y"), else: "Today"
    dollars = div(payment.amount_cents, 100)
    cents = rem(payment.amount_cents, 100)
    amount_str = "#{dollars}.#{String.pad_leading("#{cents}", 2, "0")}"

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Payment Receipt — $#{amount_str}")
    |> html_body("""
    <h2>Payment Receipt</h2>

    <p>Hi #{customer.name},</p>

    <table style="border-collapse: collapse; margin: 20px 0;">
      <tr>
        <td style="padding: 8px; font-weight: bold;">Service:</td>
        <td style="padding: 8px;">#{service_name}</td>
      </tr>
      <tr>
        <td style="padding: 8px; font-weight: bold;">Amount:</td>
        <td style="padding: 8px;">$#{amount_str}</td>
      </tr>
      <tr>
        <td style="padding: 8px; font-weight: bold;">Date:</td>
        <td style="padding: 8px;">#{paid_at}</td>
      </tr>
      <tr>
        <td style="padding: 8px; font-weight: bold;">Payment ID:</td>
        <td style="padding: 8px;"><code>#{payment.id}</code></td>
      </tr>
    </table>

    <p>Thank you for your business!</p>

    <p style="color: #666; font-size: 12px;">Driveway Detail Co · San Antonio, TX · Veteran-owned</p>
    """)
    |> text_body("""
    Payment Receipt

    Service: #{service_name}
    Amount: $#{amount_str}
    Date: #{paid_at}
    Payment ID: #{payment.id}

    Thank you! — Driveway Detail Co
    """)
  end

  @doc """
  Wash completed summary email.
  """
  def wash_completed(customer, appointment, service_name) do
    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Your #{service_name} is Complete!")
    |> html_body("""
    <h2>Your wash is complete!</h2>

    <p>Hi #{customer.name},</p>

    <p>Your <strong>#{service_name}</strong> on #{Calendar.strftime(appointment.scheduled_at, "%B %d")} has been completed.</p>

    <p>We hope you love the results! You can view details and any before/after photos in your account.</p>

    <p><a href="https://drivewaydetail.co/appointments/#{appointment.id}/status">View Details →</a></p>

    <p>Thank you for choosing Driveway Detail Co!</p>

    <p style="color: #666; font-size: 12px;">Driveway Detail Co · San Antonio, TX · Veteran-owned</p>
    """)
    |> text_body("""
    Your wash is complete!

    Hi #{customer.name},

    Your #{service_name} on #{Calendar.strftime(appointment.scheduled_at, "%B %d")} has been completed.

    View details: https://drivewaydetail.co/appointments/#{appointment.id}/status

    Thank you! — Driveway Detail Co
    """)
  end

  @doc """
  Welcome email when a subscription is created.
  """
  def subscription_created(customer, plan) do
    price = div(plan.price_cents, 100)

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Welcome to #{plan.name} — Subscription Active")
    |> html_body("""
    <h2>Welcome to your #{plan.name} plan!</h2>

    <p>Hi #{customer.name},</p>

    <p>Your <strong>#{plan.name}</strong> subscription ($#{price}/month) is now active.</p>

    <p>What's included:</p>
    <ul>
      #{if plan.basic_washes_per_month > 0, do: "<li>#{plan.basic_washes_per_month} basic wash#{if plan.basic_washes_per_month > 1, do: "es", else: ""} per month</li>", else: ""}
      #{if plan.deep_cleans_per_month > 0, do: "<li>#{plan.deep_cleans_per_month} deep clean#{if plan.deep_cleans_per_month > 1, do: "s", else: ""} per month</li>", else: ""}
      #{if plan.deep_clean_discount_percent > 0, do: "<li>#{plan.deep_clean_discount_percent}% off deep cleans</li>", else: ""}
    </ul>

    <p><a href="https://drivewaydetail.co/book">Book your first wash now →</a></p>

    <p>Thank you for choosing Driveway Detail Co!</p>

    <p style="color: #666; font-size: 12px;">Driveway Detail Co · San Antonio, TX · Veteran-owned</p>
    """)
    |> text_body("""
    Welcome to your #{plan.name} plan!

    Hi #{customer.name},

    Your #{plan.name} subscription ($#{price}/month) is now active.

    Book your first wash at https://drivewaydetail.co/book

    Thank you for choosing Driveway Detail Co!
    """)
  end

  @doc """
  Confirmation email when a subscription is cancelled.
  """
  def subscription_cancelled(customer, plan) do
    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Your #{plan.name} Subscription Has Been Cancelled")
    |> html_body("""
    <h2>Your subscription has been cancelled</h2>

    <p>Hi #{customer.name},</p>

    <p>Your <strong>#{plan.name}</strong> plan has been cancelled. You'll continue to have access until the end of your current billing period.</p>

    <p>You can resubscribe anytime at <a href="https://drivewaydetail.co/subscribe">drivewaydetail.co/subscribe</a>.</p>

    <p>We'd love to have you back!</p>

    <p style="color: #666; font-size: 12px;">Driveway Detail Co · San Antonio, TX · Veteran-owned</p>
    """)
    |> text_body("""
    Your subscription has been cancelled.

    Hi #{customer.name},

    Your #{plan.name} plan has been cancelled. Access continues until the end of your billing period.

    Resubscribe anytime: https://drivewaydetail.co/subscribe

    We'd love to have you back! — Driveway Detail Co
    """)
  end
end
