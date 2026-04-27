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
    when_str = Calendar.strftime(appointment.scheduled_at, "%B %d, %Y at %I:%M %p")
    where_str = "#{address.street}, #{address.city}, #{address.state} #{address.zip}"
    total_str = "$#{div(appointment.price_cents, 100)}"

    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Your booking is confirmed!</h2>
    <p>Hi #{customer.name},</p>
    <p>We've received your booking for <strong>#{service_type.name}</strong>. Here are the details:</p>
    <table cellpadding="0" cellspacing="0" style="margin:16px 0;">
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Service</td><td style="padding:4px 0;font-weight:600;">#{service_type.name}</td></tr>
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">When</td><td style="padding:4px 0;font-weight:600;">#{when_str}</td></tr>
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Duration</td><td style="padding:4px 0;font-weight:600;">#{appointment.duration_minutes} minutes</td></tr>
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Where</td><td style="padding:4px 0;font-weight:600;">#{where_str}</td></tr>
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Total</td><td style="padding:4px 0;font-weight:600;">#{total_str}</td></tr>
    </table>
    <p style="color:#64748b;font-size:13px;">We'll text you the day before with our 15-minute arrival window.</p>
    <p style="color:#64748b;font-size:12px;">Booking ID: <code>#{appointment.id}</code></p>
    """

    inner_text = """
    Your booking is confirmed!

    Hi #{customer.name},

    Service: #{service_type.name}
    When: #{when_str}
    Duration: #{appointment.duration_minutes} minutes
    Where: #{where_str}
    Total: #{total_str}

    Booking ID: #{appointment.id}

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
    when_str = Calendar.strftime(appointment.scheduled_at, "%B %d, %Y at %I:%M %p")
    where_str = "#{address.street}, #{address.city}, #{address.state} #{address.zip}"

    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Reminder: your wash is tomorrow</h2>
    <p>Hi #{customer.name},</p>
    <p>This is a friendly reminder that your <strong>#{service_type.name}</strong> is scheduled for tomorrow.</p>
    <table cellpadding="0" cellspacing="0" style="margin:16px 0;">
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Date &amp; Time</td><td style="padding:4px 0;font-weight:600;">#{when_str}</td></tr>
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Location</td><td style="padding:4px 0;font-weight:600;">#{where_str}</td></tr>
    </table>
    <p style="color:#64748b;font-size:13px;">Please make sure your vehicle is parked and accessible at the service location. See you tomorrow!</p>
    """

    inner_text = """
    Reminder: your wash is tomorrow

    Hi #{customer.name},

    Your #{service_type.name} is scheduled for tomorrow.

    Date & Time: #{when_str}
    Location: #{where_str}

    Please make sure your vehicle is parked and accessible.

    See you tomorrow!
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Reminder: #{service_type.name} Tomorrow")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end

  @doc """
  Deadline reminder email — sent to admin for upcoming compliance/formation tasks.
  """
  def deadline_reminder(task, category, days_before, admin_email) do
    due_str =
      if task.due_date, do: Calendar.strftime(task.due_date, "%B %d, %Y"), else: "No date set"

    notes_html = if task.description, do: "<p><strong>Notes:</strong> #{task.description}</p>", else: ""
    notes_text = if task.description, do: "Notes: #{task.description}", else: ""

    url_html =
      if task.external_url,
        do: ~s(<p>#{Layout.link("Go to website →", task.external_url)}</p>),
        else: ""

    url_text = if task.external_url, do: "URL: #{task.external_url}", else: ""

    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Compliance Deadline Reminder</h2>
    <p>The following task is due in <strong>#{days_before} day(s)</strong>:</p>
    <table cellpadding="0" cellspacing="0" style="margin:16px 0;">
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Task</td><td style="padding:4px 0;font-weight:600;">#{task.name}</td></tr>
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Category</td><td style="padding:4px 0;font-weight:600;">#{category.name}</td></tr>
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Due Date</td><td style="padding:4px 0;font-weight:600;">#{due_str}</td></tr>
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Priority</td><td style="padding:4px 0;font-weight:600;">#{task.priority}</td></tr>
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Status</td><td style="padding:4px 0;font-weight:600;">#{task.status}</td></tr>
    </table>
    #{notes_html}
    #{url_html}
    <p style="color:#64748b;font-size:13px;">Log in to your admin dashboard to update this task.</p>
    """

    inner_text = """
    Compliance Deadline Reminder

    Task: #{task.name}
    Category: #{category.name}
    Due Date: #{due_str}
    Priority: #{task.priority}
    Status: #{task.status}
    #{notes_text}
    #{url_text}

    Due in #{days_before} day(s). Log in to update.
    """

    new()
    |> to(admin_email)
    |> from(@from)
    |> subject("Deadline: #{task.name} — due in #{days_before} day(s)")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end

  @doc """
  Payment receipt — sent after a successful charge.
  """
  def payment_receipt(customer, payment, service_name) do
    paid_at =
      if payment.paid_at, do: Calendar.strftime(payment.paid_at, "%B %d, %Y"), else: "Today"

    dollars = div(payment.amount_cents, 100)
    cents = rem(payment.amount_cents, 100)
    amount_str = "#{dollars}.#{String.pad_leading("#{cents}", 2, "0")}"

    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Payment received</h2>
    <p>Hi #{customer.name},</p>
    <p>Thanks for your payment. Here are the details:</p>
    <table cellpadding="0" cellspacing="0" style="margin:16px 0;">
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Service</td><td style="padding:4px 0;font-weight:600;">#{service_name}</td></tr>
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Amount</td><td style="padding:4px 0;font-weight:600;">$#{amount_str}</td></tr>
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Date</td><td style="padding:4px 0;font-weight:600;">#{paid_at}</td></tr>
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Receipt #</td><td style="padding:4px 0;font-weight:600;font-family:monospace;">#{payment.id}</td></tr>
    </table>
    """

    inner_text = """
    Payment received

    Hi #{customer.name},

    Service: #{service_name}
    Amount: $#{amount_str}
    Date: #{paid_at}
    Receipt: #{payment.id}
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Payment Receipt — $#{amount_str}")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end

  @doc """
  Wash completed summary email.
  """
  def wash_completed(customer, appointment, service_name) do
    when_str = Calendar.strftime(appointment.scheduled_at, "%B %d")
    status_url = "https://drivewaydetailcosa.com/appointments/#{appointment.id}/status"

    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Your wash is complete!</h2>
    <p>Hi #{customer.name},</p>
    <p>Your <strong>#{service_name}</strong> on #{when_str} has been completed.</p>
    <p>We hope you love the results! You can view details and any before/after photos in your account.</p>
    <p style="margin:24px 0;">#{Layout.button("View details", status_url)}</p>
    <p style="color:#64748b;font-size:13px;">Thank you for choosing Driveway Detail Co!</p>
    """

    inner_text = """
    Your wash is complete!

    Hi #{customer.name},

    Your #{service_name} on #{when_str} has been completed.

    View details: #{status_url}

    Thank you! — Driveway Detail Co
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Your #{service_name} is Complete!")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end

  @doc """
  Tech on the way — sent when the technician departs toward the appointment.
  """
  def tech_on_the_way(customer, appointment, service_name, technician_name) do
    time = Calendar.strftime(appointment.scheduled_at, "%I:%M %p")

    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Your tech is on the way</h2>
    <p>Hi #{customer.name},</p>
    <p><strong>#{technician_name}</strong> is heading over now for your #{time} #{service_name}.</p>
    <p style="color:#64748b;font-size:13px;">We'll send another note when they arrive.</p>
    """

    inner_text = """
    Your tech is on the way

    Hi #{customer.name},

    #{technician_name} is heading over now for your #{time} #{service_name}.

    We'll send another note when they arrive.
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Your #{service_name} tech is on the way")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end

  @doc """
  Tech arrived — sent when the technician pulls up on-site, before the wash begins.
  """
  def tech_arrived(customer, _appointment, service_name, technician_name) do
    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Your tech has arrived</h2>
    <p>Hi #{customer.name},</p>
    <p><strong>#{technician_name}</strong> is on-site and about to start your #{service_name}.</p>
    <p style="color:#64748b;font-size:13px;">If your vehicle is still locked or blocked in, now's a good time to step out.</p>
    """

    inner_text = """
    Your tech has arrived

    Hi #{customer.name},

    #{technician_name} is on-site and about to start your #{service_name}.

    If your vehicle is still locked or blocked in, now's a good time to step out.
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Your tech has arrived")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end

  @doc """
  Cancellation confirmation email.
  """
  def booking_cancelled(customer, appointment, service_name) do
    when_str = Calendar.strftime(appointment.scheduled_at, "%B %d, %Y at %I:%M %p")

    reason_html =
      case appointment.cancellation_reason do
        nil -> ""
        "" -> ""
        reason -> ~s(<p><strong>Reason:</strong> #{reason}</p>)
      end

    reason_text =
      case appointment.cancellation_reason do
        nil -> ""
        "" -> ""
        reason -> "Reason: #{reason}\n"
      end

    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Your booking was cancelled</h2>
    <p>Hi #{customer.name},</p>
    <p>Your booking for <strong>#{service_name}</strong> on #{when_str} has been cancelled.</p>
    #{reason_html}
    <p>If this was a mistake or you'd like to rebook, you can do so anytime.</p>
    <p style="margin:24px 0;">#{Layout.button("Book again", "https://drivewaydetailcosa.com/book")}</p>
    """

    inner_text = """
    Your booking was cancelled

    Hi #{customer.name},

    Your booking for #{service_name} on #{when_str} has been cancelled.
    #{reason_text}
    Book again: https://drivewaydetailcosa.com/book
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Booking Cancelled - #{service_name}")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end

  @doc """
  Welcome email when a subscription is created.
  """
  def subscription_created(customer, plan) do
    price = div(plan.price_cents, 100)

    benefit_items =
      [
        if(plan.basic_washes_per_month > 0,
          do:
            {"<li>#{plan.basic_washes_per_month} basic wash#{if plan.basic_washes_per_month > 1, do: "es", else: ""} per month</li>",
             "  - #{plan.basic_washes_per_month} basic wash#{if plan.basic_washes_per_month > 1, do: "es", else: ""} per month"},
          else: nil
        ),
        if(plan.deep_cleans_per_month > 0,
          do:
            {"<li>#{plan.deep_cleans_per_month} deep clean#{if plan.deep_cleans_per_month > 1, do: "s", else: ""} per month</li>",
             "  - #{plan.deep_cleans_per_month} deep clean#{if plan.deep_cleans_per_month > 1, do: "s", else: ""} per month"},
          else: nil
        ),
        if(plan.deep_clean_discount_percent > 0,
          do:
            {"<li>#{plan.deep_clean_discount_percent}% off deep cleans</li>",
             "  - #{plan.deep_clean_discount_percent}% off deep cleans"},
          else: nil
        )
      ]
      |> Enum.reject(&is_nil/1)

    benefits_html = benefit_items |> Enum.map(&elem(&1, 0)) |> Enum.join("\n      ")
    benefits_text = benefit_items |> Enum.map(&elem(&1, 1)) |> Enum.join("\n")

    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Welcome to your #{plan.name} plan!</h2>
    <p>Hi #{customer.name},</p>
    <p>Your <strong>#{plan.name}</strong> subscription ($#{price}/month) is now active.</p>
    <p style="margin-top:16px;font-weight:600;">What's included:</p>
    <ul style="margin:8px 0 16px;padding-left:20px;">
      #{benefits_html}
    </ul>
    <p style="margin:24px 0;">#{Layout.button("Book your first wash", "https://drivewaydetailcosa.com/book")}</p>
    <p style="color:#64748b;font-size:13px;">Thank you for choosing Driveway Detail Co!</p>
    """

    inner_text = """
    Welcome to your #{plan.name} plan!

    Hi #{customer.name},

    Your #{plan.name} subscription ($#{price}/month) is now active.

    What's included:
    #{benefits_text}

    Book your first wash at https://drivewaydetailcosa.com/book

    Thank you for choosing Driveway Detail Co!
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Welcome to #{plan.name} — Subscription Active")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end

  @doc """
  Confirmation email when a subscription is cancelled.
  """
  def subscription_cancelled(customer, plan) do
    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Your subscription has been cancelled</h2>
    <p>Hi #{customer.name},</p>
    <p>Your <strong>#{plan.name}</strong> plan has been cancelled. You'll continue to have access until the end of your current billing period.</p>
    <p>You can resubscribe anytime at #{Layout.link("drivewaydetailcosa.com/subscribe", "https://drivewaydetailcosa.com/subscribe")}.</p>
    <p>We'd love to have you back!</p>
    """

    inner_text = """
    Your subscription has been cancelled.

    Hi #{customer.name},

    Your #{plan.name} plan has been cancelled. Access continues until the end of your billing period.

    Resubscribe anytime: https://drivewaydetailcosa.com/subscribe

    We'd love to have you back! — Driveway Detail Co
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Your #{plan.name} Subscription Has Been Cancelled")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end
end
