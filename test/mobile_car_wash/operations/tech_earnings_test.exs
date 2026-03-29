defmodule MobileCarWash.Operations.TechEarningsTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Operations.TechEarnings

  describe "pay_period_range/1" do
    test "Monday start (default) — today is Wednesday" do
      # Simulate a technician with Monday start
      tech = %{pay_period_start_day: 1}

      {start_date, end_date} = TechEarnings.pay_period_range(tech)

      # Period should be 7 days
      assert Date.diff(end_date, start_date) == 6

      # Start should be on Monday
      assert Date.day_of_week(start_date) == 1

      # End should be on Sunday
      assert Date.day_of_week(end_date) == 7

      # Today should be within the range
      today = Date.utc_today()
      assert Date.compare(today, start_date) in [:eq, :gt]
      assert Date.compare(today, end_date) in [:eq, :lt]
    end

    test "Sunday start" do
      tech = %{pay_period_start_day: 7}

      {start_date, end_date} = TechEarnings.pay_period_range(tech)

      assert Date.day_of_week(start_date) == 7
      assert Date.diff(end_date, start_date) == 6
    end

    test "Wednesday start" do
      tech = %{pay_period_start_day: 3}

      {start_date, end_date} = TechEarnings.pay_period_range(tech)

      assert Date.day_of_week(start_date) == 3
      assert Date.diff(end_date, start_date) == 6
    end

    test "nil defaults to Monday" do
      tech = %{pay_period_start_day: nil}

      {start_date, _end_date} = TechEarnings.pay_period_range(tech)

      assert Date.day_of_week(start_date) == 1
    end
  end

  describe "format consistency" do
    test "earnings_summary returns correct structure" do
      tech = %{
        id: Ash.UUID.generate(),
        pay_rate_cents: 3000,
        pay_period_start_day: 1
      }

      summary = TechEarnings.earnings_summary(tech)

      assert summary.washes_count == 0
      assert summary.total_cents == 0
      assert summary.rate_cents == 3000
      assert is_struct(summary.period_start, Date)
      assert is_struct(summary.period_end, Date)
      assert summary.washes == []
    end

    test "custom rate is used in summary" do
      tech = %{
        id: Ash.UUID.generate(),
        pay_rate_cents: 5000,
        pay_period_start_day: 1
      }

      summary = TechEarnings.earnings_summary(tech)

      assert summary.rate_cents == 5000
    end
  end
end
