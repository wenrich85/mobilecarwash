defmodule MobileCarWash.Notifications.SMS do
  @moduledoc """
  Composes SMS message bodies for customer notifications.
  Each function returns a plain string (≤160 chars where possible).
  """

  @doc "Booking confirmed SMS"
  def booking_confirmation(appointment, service_type, address) do
    time = format_time(appointment.scheduled_at)
    date = format_date(appointment.scheduled_at)

    "Driveway Detail Co: Your #{service_type.name} is booked for #{date} at #{time}. " <>
      "#{address.street}, #{address.city}. See you then!"
  end

  @doc "Block scheduled SMS — arrival window confirmed with exact time"
  def block_scheduled(appointment, service_type, address) do
    time = format_time(appointment.scheduled_at)
    date = format_date(appointment.scheduled_at)

    "Driveway Detail Co: Your #{service_type.name} on #{date} is confirmed for ~#{time}. " <>
      "#{address.street}, #{address.city}. See you then!"
  end

  @doc "24-hour appointment reminder SMS"
  def appointment_reminder(appointment, service_type, address) do
    time = format_time(appointment.scheduled_at)

    "Driveway Detail Co: Reminder — your #{service_type.name} is tomorrow at #{time}. " <>
      "#{address.street}, #{address.city}."
  end

  @doc "Technician en route SMS"
  def tech_on_the_way(appointment, technician) do
    time = format_time(appointment.scheduled_at)

    "Driveway Detail Co: #{technician.name} is on the way for your #{time} appointment!"
  end

  @doc "Wash completed SMS"
  def wash_completed(_appointment, service_type) do
    "Driveway Detail Co: Your #{service_type.name} is complete! " <>
      "Thanks for choosing us. We'd love a review at drivewaydetailcosa.com"
  end

  @doc "Booking cancelled SMS"
  def booking_cancelled(appointment, service_type) do
    date = format_date(appointment.scheduled_at)

    "Driveway Detail Co: Your #{service_type.name} on #{date} has been cancelled. " <>
      "Book again anytime at drivewaydetailcosa.com"
  end

  @doc "Referral credit earned SMS"
  def referral_credit(referrer, referee_name) do
    "Driveway Detail Co: You earned $10! #{referee_name} used your referral code. " <>
      "Your credit will be applied to your next booking. Thanks, #{referrer.name}!"
  end

  @doc "Post-wash review request SMS"
  def review_request(customer) do
    "Hi #{customer.name}! Thanks for choosing Driveway Detail Co. " <>
      "We'd love your review: g.page/r/drivewaydetailcosa/review"
  end

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%-I:%M %p")
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %-d")
  end
end
