defmodule Worth.Repo.Migrations.CreateOrchestrationExperiments do
  use Ecto.Migration

  def change do
    create table(:orchestration_experiments, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, null: false)
      add(:description, :text)
      add(:strategies, {:array, :string}, null: false)
      add(:prompts, {:array, :text}, null: false)
      add(:repetitions, :integer, default: 1)
      add(:base_opts, :map)
      add(:results, {:array, :map})
      add(:comparison, :map)
      add(:status, :string, default: "pending")

      timestamps(type: :utc_datetime_usec)
    end
  end
end
