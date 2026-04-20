defmodule MobileCarWash.Booking.StateMachineTest do
  use ExUnit.Case, async: true

  alias MobileCarWash.Booking.StateMachine

  defp empty_context do
    %{
      selected_service: nil,
      current_customer: nil,
      guest_mode: false,
      selected_vehicle: nil,
      selected_address: nil,
      selected_slot: nil,
      appointment: nil
    }
  end

  defp context_with(overrides) do
    Map.merge(empty_context(), overrides)
  end

  # Stub structs — StateMachine only checks nil/not-nil
  defp service, do: %{id: "svc-1", name: "Basic Wash"}
  defp customer, do: %{id: "cust-1", name: "Jane"}
  defp vehicle, do: %{id: "veh-1", make: "Honda"}
  defp address, do: %{id: "addr-1", street: "123 Main"}
  defp slot, do: ~U[2026-04-05 10:00:00Z]
  defp appointment, do: %{id: "appt-1"}

  # === Forward Transitions ===

  describe "transition(:forward, :select_service, ctx)" do
    test "advances to :auth when service selected and no customer" do
      ctx = context_with(%{selected_service: service()})
      assert {:ok, :auth} = StateMachine.transition(:forward, :select_service, ctx)
    end

    test "skips :auth → :vehicle when service selected and customer present" do
      ctx = context_with(%{selected_service: service(), current_customer: customer()})
      assert {:ok, :vehicle} = StateMachine.transition(:forward, :select_service, ctx)
    end

    test "fails when no service selected" do
      assert {:error, :missing_selected_service} =
               StateMachine.transition(:forward, :select_service, empty_context())
    end
  end

  describe "transition(:forward, :auth, ctx)" do
    test "advances to :vehicle when customer present" do
      ctx = context_with(%{selected_service: service(), current_customer: customer()})
      assert {:ok, :vehicle} = StateMachine.transition(:forward, :auth, ctx)
    end

    test "fails when no customer" do
      ctx = context_with(%{selected_service: service()})
      assert {:error, :missing_current_customer} = StateMachine.transition(:forward, :auth, ctx)
    end
  end

  describe "transition(:forward, :vehicle, ctx)" do
    test "advances to :address when vehicle selected" do
      ctx =
        context_with(%{
          selected_service: service(),
          current_customer: customer(),
          selected_vehicle: vehicle()
        })

      assert {:ok, :address} = StateMachine.transition(:forward, :vehicle, ctx)
    end

    test "fails when no vehicle" do
      ctx = context_with(%{selected_service: service(), current_customer: customer()})

      assert {:error, :missing_selected_vehicle} =
               StateMachine.transition(:forward, :vehicle, ctx)
    end
  end

  describe "transition(:forward, :address, ctx)" do
    test "advances to :photos when address selected" do
      ctx =
        context_with(%{
          selected_service: service(),
          current_customer: customer(),
          selected_vehicle: vehicle(),
          selected_address: address()
        })

      assert {:ok, :photos} = StateMachine.transition(:forward, :address, ctx)
    end

    test "fails when no address" do
      ctx =
        context_with(%{
          selected_service: service(),
          current_customer: customer(),
          selected_vehicle: vehicle()
        })

      assert {:error, :missing_selected_address} =
               StateMachine.transition(:forward, :address, ctx)
    end
  end

  describe "transition(:forward, :photos, ctx)" do
    test "advances to :schedule (optional — no guard)" do
      ctx =
        context_with(%{
          selected_service: service(),
          current_customer: customer(),
          selected_vehicle: vehicle(),
          selected_address: address()
        })

      assert {:ok, :schedule} = StateMachine.transition(:forward, :photos, ctx)
    end
  end

  describe "transition(:forward, :schedule, ctx)" do
    test "advances to :review when slot selected" do
      ctx =
        context_with(%{
          selected_service: service(),
          current_customer: customer(),
          selected_vehicle: vehicle(),
          selected_address: address(),
          selected_slot: slot()
        })

      assert {:ok, :review} = StateMachine.transition(:forward, :schedule, ctx)
    end

    test "fails when no slot" do
      ctx =
        context_with(%{
          selected_service: service(),
          current_customer: customer(),
          selected_vehicle: vehicle(),
          selected_address: address()
        })

      assert {:error, :missing_selected_slot} = StateMachine.transition(:forward, :schedule, ctx)
    end
  end

  describe "transition(:forward, :review, ctx)" do
    test "advances to :confirmed" do
      ctx =
        context_with(%{
          selected_service: service(),
          current_customer: customer(),
          selected_vehicle: vehicle(),
          selected_address: address(),
          selected_slot: slot()
        })

      assert {:ok, :confirmed} = StateMachine.transition(:forward, :review, ctx)
    end
  end

  describe "transition(:forward, :confirmed, ctx)" do
    test "cannot advance past confirmed" do
      assert {:error, :already_confirmed} =
               StateMachine.transition(:forward, :confirmed, empty_context())
    end
  end

  # === Backward Transitions ===

  describe "transition(:back, ...)" do
    test "vehicle → auth (no pre-existing customer)" do
      ctx = context_with(%{selected_service: service()})
      assert {:ok, :auth} = StateMachine.transition(:back, :vehicle, ctx)
    end

    test "vehicle → select_service (skips auth when customer present)" do
      ctx = context_with(%{selected_service: service(), current_customer: customer()})
      assert {:ok, :select_service} = StateMachine.transition(:back, :vehicle, ctx)
    end

    test "address → vehicle" do
      assert {:ok, :vehicle} = StateMachine.transition(:back, :address, empty_context())
    end

    test "photos → address" do
      assert {:ok, :address} = StateMachine.transition(:back, :photos, empty_context())
    end

    test "schedule → photos" do
      assert {:ok, :photos} = StateMachine.transition(:back, :schedule, empty_context())
    end

    test "review → schedule" do
      assert {:ok, :schedule} = StateMachine.transition(:back, :review, empty_context())
    end

    test "select_service has no previous" do
      assert {:error, :no_prev_step} =
               StateMachine.transition(:back, :select_service, empty_context())
    end

    test "confirmed cannot go back" do
      assert {:error, :cannot_go_back} =
               StateMachine.transition(:back, :confirmed, empty_context())
    end
  end

  # === can_be_on?/2 ===

  describe "can_be_on?/2" do
    test "select_service is always valid" do
      assert StateMachine.can_be_on?(:select_service, empty_context())
    end

    test "auth requires service" do
      refute StateMachine.can_be_on?(:auth, empty_context())
      assert StateMachine.can_be_on?(:auth, context_with(%{selected_service: service()}))
    end

    test "vehicle requires service + customer" do
      refute StateMachine.can_be_on?(:vehicle, context_with(%{selected_service: service()}))

      assert StateMachine.can_be_on?(
               :vehicle,
               context_with(%{selected_service: service(), current_customer: customer()})
             )
    end

    test "address requires service + customer + vehicle" do
      refute StateMachine.can_be_on?(
               :address,
               context_with(%{
                 selected_service: service(),
                 current_customer: customer()
               })
             )

      assert StateMachine.can_be_on?(
               :address,
               context_with(%{
                 selected_service: service(),
                 current_customer: customer(),
                 selected_vehicle: vehicle()
               })
             )
    end

    test "schedule requires all up to address" do
      assert StateMachine.can_be_on?(
               :schedule,
               context_with(%{
                 selected_service: service(),
                 current_customer: customer(),
                 selected_vehicle: vehicle(),
                 selected_address: address()
               })
             )
    end

    test "review requires all up to slot" do
      assert StateMachine.can_be_on?(
               :review,
               context_with(%{
                 selected_service: service(),
                 current_customer: customer(),
                 selected_vehicle: vehicle(),
                 selected_address: address(),
                 selected_slot: slot()
               })
             )
    end

    test "confirmed requires appointment" do
      refute StateMachine.can_be_on?(:confirmed, empty_context())
      assert StateMachine.can_be_on?(:confirmed, context_with(%{appointment: appointment()}))
    end
  end

  # === resolve_step/2 (reconnection recovery) ===

  describe "resolve_step/2" do
    test "returns claimed step when valid" do
      ctx =
        context_with(%{
          selected_service: service(),
          current_customer: customer(),
          selected_vehicle: vehicle()
        })

      assert :address == StateMachine.resolve_step(:address, ctx)
    end

    test "walks back when claimed step is invalid" do
      # Claim :address but vehicle is missing — should resolve to :vehicle
      ctx = context_with(%{selected_service: service(), current_customer: customer()})
      assert :vehicle == StateMachine.resolve_step(:address, ctx)
    end

    test "walks all the way back to select_service when nothing set" do
      assert :select_service == StateMachine.resolve_step(:review, empty_context())
    end

    test "skips auth when customer present and resolving to auth step" do
      ctx = context_with(%{selected_service: service(), current_customer: customer()})
      assert :vehicle == StateMachine.resolve_step(:auth, ctx)
    end

    test "returns select_service for empty context regardless of claim" do
      assert :select_service == StateMachine.resolve_step(:schedule, empty_context())
    end
  end
end
