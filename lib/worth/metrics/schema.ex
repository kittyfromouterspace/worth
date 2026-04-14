defmodule Worth.Metrics.Schema do
  @moduledoc """
  Ecto schemas for orchestration metrics tables.
  """

  defmodule SessionMetric do
    @moduledoc false
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "session_metrics" do
      field(:session_id, :string)
      field(:run_id, :string)
      field(:strategy, :string, default: "default")
      field(:mode, :string)
      field(:workspace, :string)
      field(:started_at, :utc_datetime_usec)
      field(:completed_at, :utc_datetime_usec)
      field(:status, :string, default: "running")
      field(:total_cost_usd, :float, default: 0.0)
      field(:total_tokens_in, :integer, default: 0)
      field(:total_tokens_out, :integer, default: 0)
      field(:total_turns, :integer, default: 0)
      field(:total_tool_calls, :integer, default: 0)
      field(:prompt_hash, :string)
      field(:model_id, :string)

      timestamps(type: :utc_datetime_usec)
    end
  end

  defmodule TurnMetric do
    @moduledoc false
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "turn_metrics" do
      field(:session_id, :string)
      field(:turn_number, :integer)
      field(:started_at, :utc_datetime_usec)
      field(:duration_ms, :integer)
      field(:cost_usd, :float, default: 0.0)
      field(:tokens_in, :integer, default: 0)
      field(:tokens_out, :integer, default: 0)
      field(:stop_reason, :string)
      field(:model_id, :string)
      field(:phase, :string)

      timestamps(type: :utc_datetime_usec)
    end
  end

  defmodule ToolCallMetric do
    @moduledoc false
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "tool_call_metrics" do
      field(:session_id, :string)
      field(:turn_number, :integer)
      field(:tool_name, :string)
      field(:called_at, :utc_datetime_usec)
      field(:duration_ms, :integer)
      field(:success, :boolean, default: true)
      field(:error_type, :string)
      field(:result_size_bytes, :integer)

      timestamps(type: :utc_datetime_usec)
    end
  end

  defmodule StrategyMetric do
    @moduledoc false
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "strategy_metrics" do
      field(:session_id, :string)
      field(:metric_key, :string)
      field(:metric_value, :float)
      field(:recorded_at, :utc_datetime_usec)
      field(:metadata, :string)

      timestamps(type: :utc_datetime_usec)
    end
  end
end
