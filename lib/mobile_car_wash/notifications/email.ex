defmodule MobileCarWash.Notifications.Email do
  @moduledoc """
  Email templates for the mobile car wash application.
  Uses Swoosh for email composition.
  """
  import Swoosh.Email
  alias MobileCarWash.Notifications.Email.Layout

  @from {"Driveway Detail Co", "noreply@drivewaydetailcosa.com"}

  @doc """
  Email verification link — sent after signup. 24-hour lifetime; link
  carries a one-shot JWT with the customer's subject + email baked in.
  """
  def verify_email(customer, verification_link) do
    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Welcome, #{customer.name}!</h2>
    <p>Thanks for signing up with Driveway Detail Co. Please verify your
    email so we can send you booking confirmations, reminders, and receipts.</p>
    <p style="margin:24px 0;">#{Layout.button("Verify my email", verification_link)}</p>
    <p style="color:#64748b;font-size:12px;">The link expires in 24 hours.
    If you didn't create this account, you can safely ignore this email.</p>
    """

    inner_text = """
    Welcome, #{customer.name}!

    Thanks for signing up with Driveway Detail Co. Please verify your email
    so we can send you booking confirmations, reminders, and receipts.

    Verify: #{verification_link}

    The link expires in 24 hours. If you didn't create this account, you
    can safely ignore this email.
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Verify your email for Driveway Detail Co")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end

  @doc """
  Booking confirmation email — sent after successful payment.
  """
  def booking_confirmation(appointment, service_type, customer, address) do
    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Your booking is confirmed!</h2>
    <p>Hi #{customer.name},</p>
    <p>We've received your booking for <strong>#{service_type.name}</strong>.</p>
    <table cellpadding="0" cellspacing="0" style="margin:16px 0;">
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Service</td><td style="padding:4px 0;font-weight:600;">#{service_type.name}</td></tr>
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">When</td><td style="padding:4px 0;font-weight:600;">#{appointment.scheduled_at}</td></tr>
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Where</td><td style="padding:4px 0;font-weight:600;">#{address}</td></tr>
    </table>
    <p style="color:#64748b;font-size:13px;">We'll text you the day before with our 15-minute arrival window.</p>
    """

    inner_text = """
    Your booking is confirmed!

    Hi #{customer.name},

    We've received your booking for #{service_type.name}.

    Service: #{service_type.name}
    When: #{appointment.scheduled_at}
    Where: #{address}

    We'll text you the day before with our 15-minute arrival window.
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Booking Confirmed - #{service_type.name}")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
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
    due_str =
      if task.due_date, do: Calendar.strftime(task.due_date, "%B %d, %Y"), else: "No date set"

    url_line =
      if task.external_url,
        do: "<p><a href=\"#{task.external_url}\">Go to website →</a></p>",
        else: ""

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
  Payment receipt — sent after a successful charge.
  """
  def payment_receipt(customer, payment, service_name) do
    amount_dollars = :erlang.float_to_binary(payment.amount_cents / 100, decimals: 2)

    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Payment received</h2>
    <p>Hi #{customer.name},</p>
    <p>Thanks for your payment. Here are the details:</p>
    <table cellpadding="0" cellspacing="0" style="margin:16px 0;">
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Service</td><td style="padding:4px 0;font-weight:600;">#{service_name}</td></tr>
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Amount</td><td style="padding:4px 0;font-weight:600;">$#{amount_dollars}</td></tr>
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Receipt #</td><td style="padding:4px 0;font-weight:600;font-family:monospace;">#{payment.id}</td></tr>
    </table>
    """

    inner_text = """
    Payment received

    Hi #{customer.name},

    Service: #{service_name}
    Amount: $#{amount_dollars}
    Receipt: #{payment.id}
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Payment Receipt — Driveway Detail Co")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
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

    <p><a href="https://drivewaydetailcosa.com/appointments/#{appointment.id}/status">View Details →</a></p>

    <p>Thank you for choosing Driveway Detail Co!</p>

    <p style="color: #666; font-size: 12px;">Driveway Detail Co · San Antonio, TX · Veteran-owned</p>
    """)
    |> text_body("""
    Your wash is complete!

    Hi #{customer.name},

    Your #{service_name} on #{Calendar.strftime(appointment.scheduled_at, "%B %d")} has been completed.

    View details: https://drivewaydetailcosa.com/appointments/#{appointment.id}/status

    Thank you! — Driveway Detail Co
    """)
  end

  @doc """
  Tech on the way — sent when the technician departs toward the appointment.
  """
  def tech_on_the_way(customer, appointment, service_name, technician_name) do
    time = Calendar.strftime(appointment.scheduled_at, "%I:%M %p")

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Your #{service_name} tech is on the way")
    |> html_body("""
    <h2>Your tech is on the way</h2>

    <p>Hi #{customer.name},</p>

    <p><strong>#{technician_name}</strong> is heading over now for your #{time} #{service_name}.</p>

    <p>We'll send another note when they arrive.</p>

    <p style="color: #666; font-size: 12px;">Driveway Detail Co · San Antonio, TX · Veteran-owned</p>
    """)
    |> text_body("""
    Your tech is on the way

    Hi #{customer.name},

    #{technician_name} is heading over now for your #{time} #{service_name}.

    We'll send another note when they arrive.

    — Driveway Detail Co
    """)
  end

  @doc """
  Tech arrived — sent when the technician pulls up on-site, before the wash begins.
  """
  def tech_arrived(customer, _appointment, service_name, technician_name) do
    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Your tech has arrived")
    |> html_body("""
    <h2>Your tech has arrived</h2>

    <p>Hi #{customer.name},</p>

    <p><strong>#{technician_name}</strong> is on-site and about to start your #{service_name}.</p>

    <p>If your vehicle is still locked or blocked in, now's a good time to step out.</p>

    <p style="color: #666; font-size: 12px;">Driveway Detail Co · San Antonio, TX · Veteran-owned</p>
    """)
    |> text_body("""
    Your tech has arrived

    Hi #{customer.name},

    #{technician_name} is on-site and about to start your #{service_name}.

    If your vehicle is still locked or blocked in, now's a good time to step out.

    — Driveway Detail Co
    """)
  end

  @doc """
  Cancellation confirmation email.
  """
  def booking_cancelled(customer, appointment, service_name) do
    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Your booking was cancelled</h2>
    <p>Hi #{customer.name},</p>
    <p>Your booking for <strong>#{service_name}</strong> on #{appointment.scheduled_at} has been cancelled.</p>
    <p>If this was a mistake or you'd like to rebook, you can do so anytime.</p>
    <p style="margin:24px 0;">#{Layout.button("Book again", "https://drivewaydetailcosa.com/book")}</p>
    """

    inner_text = """
    Your booking was cancelled

    Hi #{customer.name},

    Your booking for #{service_name} on #{appointment.scheduled_at} has been cancelled.

    Book again: https://drivewaydetailcosa.com/book
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Booking Cancelled — #{service_name}")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
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

    <p><a href="https://drivewaydetailcosa.com/book">Book your first wash now →</a></p>

    <p>Thank you for choosing Driveway Detail Co!</p>

    <p style="color: #666; font-size: 12px;">Driveway Detail Co · San Antonio, TX · Veteran-owned</p>
    """)
    |> text_body("""
    Welcome to your #{plan.name} plan!

    Hi #{customer.name},

    Your #{plan.name} subscription ($#{price}/month) is now active.

    Book your first wash at https://drivewaydetailcosa.com/book

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

    <p>You can resubscribe anytime at <a href="https://drivewaydetailcosa.com/subscribe">drivewaydetailcosa.com/subscribe</a>.</p>

    <p>We'd love to have you back!</p>

    <p style="color: #666; font-size: 12px;">Driveway Detail Co · San Antonio, TX · Veteran-owned</p>
    """)
    |> text_body("""
    Your subscription has been cancelled.

    Hi #{customer.name},

    Your #{plan.name} plan has been cancelled. Access continues until the end of your billing period.

    Resubscribe anytime: https://drivewaydetailcosa.com/subscribe

    We'd love to have you back! — Driveway Detail Co
    """)
  end
end
