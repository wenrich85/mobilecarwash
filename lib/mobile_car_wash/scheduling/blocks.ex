defmodule MobileCarWash.Scheduling.Blocks do
  @moduledoc """
  Admin block management helpers: quick create, and a guarded delete that
  refuses to remove a block that still holds appointments.
  """

  alias MobileCarWash.Scheduling.AppointmentBlock

  @doc "Creates an appointment block. Thin wrapper over the resource :create action."
  def create_block(attrs) do
    AppointmentBlock
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false)
  end

  @doc """
  Deletes a block only if it holds no appointments. Returns `:ok`,
  `{:error, :block_has_appointments}`, or `{:error, :block_not_found}`.
  """
  def delete_block(id) do
    case Ash.get(AppointmentBlock, id, load: [:appointment_count], authorize?: false) do
      {:ok, %{appointment_count: count} = block} when count in [0, nil] ->
        case Ash.destroy(block, authorize?: false) do
          :ok -> :ok
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:ok, _block} ->
        {:error, :block_has_appointments}

      {:error, _} ->
        {:error, :block_not_found}
    end
  end

  @doc """
  Cancels a block by setting its status to `:cancelled`, leaving its appointments
  intact for manual rebooking. Unlike `delete_block/1`, this is the path for
  booked blocks. Returns `:ok`, or `{:error, :block_not_found}`.
  """
  def cancel_block(id) do
    case Ash.get(AppointmentBlock, id, authorize?: false) do
      {:ok, block} ->
        case block
             |> Ash.Changeset.for_update(:update, %{status: :cancelled})
             |> Ash.update(authorize?: false) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, _} ->
        {:error, :block_not_found}
    end
  end
end
