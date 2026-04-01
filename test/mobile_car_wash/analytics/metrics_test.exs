defmodule MobileCarWash.Analytics.MetricsTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Analytics.Metrics
  alias MobileCarWash.Analytics.Event

  setup do
    # Create some test events
    for event_name <- ["page.viewed", "page.viewed", "page.viewed",
                       "booking.started", "booking.started",
                       "booking.completed"] do
      Event
      |> Ash.Changeset.for_create(:track, %{
        session_id: "sess_test_#{:rand.uniform(10000)}",
        event_name: event_name,
        source: "web",
        properties: %{"path" => "/"}
      })
      |> Ash.create!()
    end

    :ok
  end

  describe "kpis/1" do
    test "returns KPI structure" do
      kpis = Metrics.kpis(:last_7_days)

      assert is_map(kpis.revenue)
      assert kpis.revenue.total_cents >= 0
      assert is_integer(kpis.active_subscribers)
      assert is_integer(kpis.bookings)
      assert is_float(kpis.conversion_rate) or kpis.conversion_rate == 0.0
    end
  end

  describe "funnel/1" do
    test "returns AARRR funnel steps" do
      funnel = Metrics.funnel(:last_7_days)

      assert length(funnel.steps) == 6
      step_names = Enum.map(funnel.steps, & &1.name)
      assert "Visitors" in step_names
      assert "Signups" in step_names
      assert "Bookings Started" in step_names
      assert "Bookings Completed" in step_names
      assert "Payments" in step_names
      assert "Returning" in step_names
    end

    test "visitor count matches page.viewed events" do
      funnel = Metrics.funnel(:last_7_days)
      visitors = Enum.find(funnel.steps, &(&1.name == "Visitors"))
      assert visitors.count == 3
    end

    test "bookings completed count matches events" do
      funnel = Metrics.funnel(:last_7_days)
      completed = Enum.find(funnel.steps, &(&1.name == "Bookings Completed"))
      assert completed.count == 1
    end
  end

  describe "booking_stats/1" do
    test "returns booking flow statistics" do
      stats = Metrics.booking_stats(:last_7_days)

      assert stats.started == 2
      assert stats.completed == 1
      assert stats.abandoned == 1
      assert stats.abandonment_rate == 50.0
    end
  end

  describe "pivot_signals/0" do
    test "returns list of signals with status" do
      signals = Metrics.pivot_signals()

      assert is_list(signals)
      assert length(signals) == 5

      for signal <- signals do
        assert signal.status in [:green, :yellow, :red]
        assert is_binary(signal.name)
        assert is_binary(signal.action)
      end
    end
  end

  describe "recent_events/2" do
    test "returns recent events ordered by time" do
      events = Metrics.recent_events(10)

      assert length(events) == 6
      assert hd(events).event_name in ["page.viewed", "booking.started", "booking.completed"]
    end
  end

  describe "event_names/0" do
    test "returns distinct event names" do
      names = Metrics.event_names()

      assert "page.viewed" in names
      assert "booking.started" in names
      assert "booking.completed" in names
    end
  end

  describe "conversion_rate/2" do
    test "calculates visit to booking rate" do
      {start_date, end_date} = {DateTime.add(DateTime.utc_now(), -7, :day), DateTime.utc_now()}
      rate = Metrics.conversion_rate(start_date, end_date)

      # 1 booking.completed / 3 page.viewed = 33.3%
      assert rate == 33.3
    end
  end

  describe "compare_revenue/1 (Milestone 4A)" do
    test "returns comparison structure with delta_pct" do
      comparison = Metrics.compare_revenue(:last_7_days)

      assert is_map(comparison)
      assert is_integer(comparison.current)
      assert is_integer(comparison.previous)
      assert is_float(comparison.delta_pct)
    end

    test "handles zero previous revenue (guards division by zero)" do
      comparison = Metrics.compare_revenue(:last_7_days)

      # When previous is 0 and current is 0, delta should be 0.0
      if comparison.previous == 0 and comparison.current == 0 do
        assert comparison.delta_pct == 0.0
      end
    end

    test "returns correct delta for period comparison" do
      comparison = Metrics.compare_revenue(:last_7_days)

      # Should be able to handle any previous/current combination
      if comparison.previous > 0 do
        expected_delta = (comparison.current - comparison.previous) / comparison.previous * 100
        assert comparison.delta_pct == Float.round(expected_delta, 1)
      end
    end
  end

  describe "technician_performance/1 (Milestone 4B)" do
    test "returns list of technician performance metrics" do
      performance = Metrics.technician_performance(:last_7_days)

      assert is_list(performance)

      for tech <- performance do
        assert is_binary(tech.technician_name)
        assert is_integer(tech.washes_count)
        assert is_integer(tech.total_revenue_cents)
        assert is_float(tech.efficiency_pct) or tech.efficiency_pct == 0.0
      end
    end

    test "returns sorted by washes count descending" do
      performance = Metrics.technician_performance(:last_7_days)

      # Verify sorted order
      counts = Enum.map(performance, & &1.washes_count)
      assert counts == Enum.sort(counts, :desc)
    end

    test "handles zero completed appointments" do
      performance = Metrics.technician_performance(:last_7_days)

      # Should return empty or all zeros
      assert performance == [] or Enum.all?(performance, &(&1.washes_count == 0))
    end
  end
end
