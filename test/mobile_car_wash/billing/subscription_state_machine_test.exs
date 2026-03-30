defmodule MobileCarWash.Billing.SubscriptionStateMachineTest do
  use ExUnit.Case, async: true

  alias MobileCarWash.Billing.SubscriptionStateMachine, as: SM

  defp empty_ctx, do: %{selected_plan: nil, current_customer: nil}
  defp with_plan(ctx), do: %{ctx | selected_plan: %{id: "plan-1"}}
  defp with_customer(ctx), do: %{ctx | current_customer: %{id: "cust-1"}}

  describe "steps/0" do
    test "returns all steps in order" do
      assert SM.steps() == [:select_plan, :auth, :review, :checkout]
    end
  end

  describe "forward transitions" do
    test "select_plan → auth when plan selected" do
      ctx = empty_ctx() |> with_plan()
      assert {:ok, :auth} = SM.transition(:forward, :select_plan, ctx)
    end

    test "select_plan blocked without plan" do
      assert {:error, :missing_selected_plan} = SM.transition(:forward, :select_plan, empty_ctx())
    end

    test "auth → review when customer present" do
      ctx = empty_ctx() |> with_plan() |> with_customer()
      assert {:ok, :review} = SM.transition(:forward, :auth, ctx)
    end

    test "auth blocked without customer" do
      ctx = empty_ctx() |> with_plan()
      assert {:error, :missing_current_customer} = SM.transition(:forward, :auth, ctx)
    end

    test "review → checkout" do
      ctx = empty_ctx() |> with_plan() |> with_customer()
      assert {:ok, :checkout} = SM.transition(:forward, :review, ctx)
    end

    test "checkout has no next step" do
      ctx = empty_ctx() |> with_plan() |> with_customer()
      assert {:error, :already_at_checkout} = SM.transition(:forward, :checkout, ctx)
    end
  end

  describe "auth auto-skip" do
    test "skips auth forward when customer present" do
      ctx = empty_ctx() |> with_plan() |> with_customer()
      assert {:ok, :review} = SM.transition(:forward, :select_plan, ctx)
    end

    test "skips auth backward when customer present" do
      ctx = empty_ctx() |> with_plan() |> with_customer()
      assert {:ok, :select_plan} = SM.transition(:back, :review, ctx)
    end

    test "does not skip auth when no customer" do
      ctx = empty_ctx() |> with_plan()
      assert {:ok, :auth} = SM.transition(:forward, :select_plan, ctx)
    end
  end

  describe "back transitions" do
    test "review → auth (no customer)" do
      ctx = empty_ctx() |> with_plan()
      assert {:ok, :auth} = SM.transition(:back, :review, ctx)
    end

    test "auth → select_plan" do
      ctx = empty_ctx() |> with_plan()
      assert {:ok, :select_plan} = SM.transition(:back, :auth, ctx)
    end

    test "select_plan has no prev" do
      assert {:error, :no_prev_step} = SM.transition(:back, :select_plan, empty_ctx())
    end

    test "checkout → review" do
      ctx = empty_ctx() |> with_plan() |> with_customer()
      assert {:ok, :review} = SM.transition(:back, :checkout, ctx)
    end
  end

  describe "can_be_on?/2" do
    test "always can be on select_plan" do
      assert SM.can_be_on?(:select_plan, empty_ctx())
    end

    test "auth requires plan" do
      refute SM.can_be_on?(:auth, empty_ctx())
      assert SM.can_be_on?(:auth, empty_ctx() |> with_plan())
    end

    test "review requires plan and customer" do
      refute SM.can_be_on?(:review, empty_ctx() |> with_plan())
      assert SM.can_be_on?(:review, empty_ctx() |> with_plan() |> with_customer())
    end

    test "checkout requires plan and customer" do
      assert SM.can_be_on?(:checkout, empty_ctx() |> with_plan() |> with_customer())
    end
  end

  describe "resolve_step/2" do
    test "returns claimed step if valid" do
      ctx = empty_ctx() |> with_plan() |> with_customer()
      assert SM.resolve_step(:review, ctx) == :review
    end

    test "walks back to highest valid step" do
      ctx = empty_ctx() |> with_plan()
      # Can't be on review without customer, walks back to auth
      assert SM.resolve_step(:review, ctx) == :auth
    end

    test "walks back to select_plan if nothing selected" do
      assert SM.resolve_step(:review, empty_ctx()) == :select_plan
    end

    test "skips auth in resolve when customer present" do
      ctx = empty_ctx() |> with_plan() |> with_customer()
      assert SM.resolve_step(:auth, ctx) == :review
    end
  end
end
