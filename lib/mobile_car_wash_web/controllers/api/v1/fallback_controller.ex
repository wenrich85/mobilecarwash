defmodule MobileCarWashWeb.Api.V1.FallbackController do
  @moduledoc """
  Shared error handling for API v1 controllers. Normalizes Ash errors,
  changeset errors, and atom error codes into a consistent JSON shape:

      {"error": "message", "details": {...}}
  """
  use MobileCarWashWeb, :controller

  def call(conn, {:error, %Ash.Error.Forbidden{}}), do: forbidden(conn)
  def call(conn, {:error, %Ash.Error.Invalid{} = error}), do: unprocessable(conn, error)
  def call(conn, {:error, :not_found}), do: not_found(conn)
  def call(conn, {:error, :unauthorized}), do: unauthorized(conn)

  def call(conn, {:error, code}) when is_atom(code) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: to_string(code)})
  end

  def call(conn, {:error, reason}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: inspect(reason)})
  end

  defp unauthorized(conn) do
    conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"})
  end

  defp forbidden(conn) do
    conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
  end

  defp not_found(conn) do
    conn |> put_status(:not_found) |> json(%{error: "not_found"})
  end

  defp unprocessable(conn, %Ash.Error.Invalid{errors: errors}) do
    messages =
      Enum.map(errors, fn
        %{field: field, message: msg} when not is_nil(field) -> "#{field}: #{msg}"
        %{message: msg} -> msg
        other -> inspect(other)
      end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "invalid", details: messages})
  end
end
