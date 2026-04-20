defmodule MobileCarWash.Features.CustomerBookingTest do
  @moduledoc """
  BDD Feature: Customer books a car wash

  As a customer
  I want to book a car wash from the landing page
  So that I can get my car cleaned at my location

  Scenario: Customer visits landing page and sees service options
    Given I visit the landing page
    Then I should see the "Basic Wash" service at $50
    And I should see the "Deep Clean & Detail" service at $200
    And I should see subscription plans

  Scenario: Customer starts booking flow
    Given I visit the landing page
    When I click "Book Now" on the Basic Wash
    Then I should be prompted to sign up or log in

  Scenario: Customer signs up and completes booking
    Given I am a new customer
    When I sign up with valid credentials
    And I add my vehicle details
    And I add my address
    And I select a time slot
    And I complete payment
    Then I should see a booking confirmation
    And I should receive a confirmation email
  """
  use MobileCarWashWeb.ConnCase, async: true

  alias MobileCarWash.Scheduling.ServiceType
  alias MobileCarWash.Billing.SubscriptionPlan

  require Ash.Query

  defp create_service_types(_context) do
    basic =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "basic_wash",
        description: "Exterior hand wash",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create!()

    deep =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Deep Clean & Detail",
        slug: "deep_clean",
        description: "Full interior and exterior detail",
        base_price_cents: 20_000,
        duration_minutes: 120
      })
      |> Ash.create!()

    %{basic_wash: basic, deep_clean: deep}
  end

  defp create_subscription_plans(_context) do
    plans =
      for attrs <- [
            %{
              name: "Basic",
              slug: "basic",
              price_cents: 9_000,
              basic_washes_per_month: 2,
              deep_cleans_per_month: 0,
              deep_clean_discount_percent: 25,
              description: "2 basic washes per month"
            },
            %{
              name: "Standard",
              slug: "standard",
              price_cents: 12_500,
              basic_washes_per_month: 4,
              deep_cleans_per_month: 0,
              deep_clean_discount_percent: 30,
              description: "4 basic washes per month"
            },
            %{
              name: "Premium",
              slug: "premium",
              price_cents: 20_000,
              basic_washes_per_month: 3,
              deep_cleans_per_month: 1,
              deep_clean_discount_percent: 50,
              description: "Premium plan"
            }
          ] do
        SubscriptionPlan
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create!()
      end

    %{plans: plans}
  end

  describe "landing page" do
    setup [:create_service_types]

    test "displays available service types", %{basic_wash: basic, deep_clean: deep} do
      assert basic.name == "Basic Wash"
      assert basic.base_price_cents == 5_000

      assert deep.name == "Deep Clean & Detail"
      assert deep.base_price_cents == 20_000

      # Verify we can read them back from the DB
      services = Ash.read!(ServiceType)
      assert length(services) == 2

      # TODO: When landing page LiveView is built, test the actual page render:
      # conn = get(conn, ~p"/")
      # assert html_response(conn, 200) =~ "Basic Wash"
      # assert html_response(conn, 200) =~ "$50"
    end

    setup [:create_subscription_plans]

    test "displays subscription plans", %{plans: plans} do
      assert length(plans) == 3

      basic = Enum.find(plans, &(&1.slug == "basic"))
      standard = Enum.find(plans, &(&1.slug == "standard"))
      premium = Enum.find(plans, &(&1.slug == "premium"))

      assert basic.price_cents == 9_000
      assert basic.basic_washes_per_month == 2
      assert basic.deep_clean_discount_percent == 25

      assert standard.price_cents == 12_500
      assert standard.basic_washes_per_month == 4

      assert premium.price_cents == 20_000
      assert premium.basic_washes_per_month == 3
      assert premium.deep_cleans_per_month == 1
      assert premium.deep_clean_discount_percent == 50
    end
  end

  describe "customer registration" do
    test "creates a new customer with valid credentials" do
      assert {:ok, customer} =
               MobileCarWash.Accounts.Customer
               |> Ash.Changeset.for_create(:register_with_password, %{
                 email: "test@example.com",
                 password: "Password123!",
                 password_confirmation: "Password123!",
                 name: "Test Customer",
                 phone: "512-555-0100"
               })
               |> Ash.create()

      assert to_string(customer.email) == "test@example.com"
      assert customer.name == "Test Customer"
      assert customer.phone == "512-555-0100"
    end

    test "rejects duplicate email registration" do
      attrs = %{
        email: "duplicate@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "First Customer"
      }

      # First registration succeeds
      assert {:ok, _} =
               MobileCarWash.Accounts.Customer
               |> Ash.Changeset.for_create(:register_with_password, attrs)
               |> Ash.create()

      # Duplicate email fails
      assert {:error, _} =
               MobileCarWash.Accounts.Customer
               |> Ash.Changeset.for_create(:register_with_password, %{
                 attrs
                 | name: "Second Customer"
               })
               |> Ash.create()
    end
  end

  describe "event tracking" do
    test "tracks a page view event" do
      assert {:ok, event} =
               MobileCarWash.Analytics.Event
               |> Ash.Changeset.for_create(:track, %{
                 session_id: "sess_abc123",
                 event_name: "page.viewed",
                 source: "web",
                 properties: %{
                   "path" => "/",
                   "referrer" => "https://google.com",
                   "utm_source" => "google",
                   "utm_medium" => "cpc"
                 }
               })
               |> Ash.create()

      assert event.event_name == "page.viewed"
      assert event.properties["utm_source"] == "google"
      assert event.session_id == "sess_abc123"
    end
  end

  describe "audit logging" do
    test "logs an action to the audit trail" do
      assert {:ok, log} =
               MobileCarWash.Audit.AuditLog
               |> Ash.Changeset.for_create(:log, %{
                 action: "customer.registered",
                 resource_type: "Customer",
                 resource_id: Ash.UUID.generate(),
                 actor_type: "system",
                 metadata: %{"ip" => "127.0.0.1", "user_agent" => "test"},
                 changes: %{"email" => "new@example.com"}
               })
               |> Ash.create()

      assert log.action == "customer.registered"
      assert log.resource_type == "Customer"
      assert log.metadata["ip"] == "127.0.0.1"
    end
  end
end
