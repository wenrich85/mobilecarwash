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
end
