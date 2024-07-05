defmodule Rsmqx do
  @moduledoc """
  Documentation for `Rsmqx`.
  """

  def create_queue(conn, queue_name, opts \\ []) do
    key = queue_key(queue_name)

    with :ok <- validate_params([{:queue_name, queue_name} | opts]),
         :ok <- do_create_queue(conn, key, opts),
         :ok <- index_queue(conn, queue_name) do
      :ok
    else
      error -> error
    end
  end

  defp do_create_queue(conn, key, opts) do
    pipeline =
      [
        ["hsetnx", key, :vt, opts[:vt] || 30],
        ["hsetnx", key, :delay, opts[:delay] || 0],
        ["hsetnx", key, :maxsize, opts[:maxsize] || 65536]
      ]

    Redix.transaction_pipeline(conn, pipeline)
    |> handle_result([1, 1, 1], :queue_exists)
  end

  defp index_queue(conn, queue_name) do
    Redix.command(conn, ["sadd", "rsmq:QUEUES", queue_name])
    |> handle_result(1, :queue_index_exists)
  end

  defp queue_key(queue_name), do: "rsmq:#{queue_name}:Q"

  defp handle_result({:error, error}, _, _), do: {:error, error}
  defp handle_result({:ok, resp}, expected, _) when resp == expected, do: :ok
  defp handle_result(_, _, error_message), do: {:error, error_message}

  defp validate_params(opts) do
    %{opts: opts, errors: []}
    |> validate_opt(:queue_name, &is_binary/1, "must be string")
    |> validate_opt(:vt, &is_integer/1, "must be integer")
    |> validate_opt(:delay, &is_integer/1, "must be integer")
    |> validate_opt(:maxsize, &is_integer/1, "must be integer")
    |> case do
      %{errors: []} -> :ok
      %{errors: errors} -> {:error, %{message: :invalid_params, errors: errors}}
    end
  end

  defp validate_opt(%{opts: opts} = validator, key, function, message) do
    if !Keyword.has_key?(opts, key) || function.(opts[key]) do
      validator
    else
      validator
      |> Map.update!(:errors, &(&1 ++ [{key, message}]))
    end
  end
end
