defmodule Worth.Repo.Migrations.AddPlaintextValueToSettings do
  use Ecto.Migration

  def change do
    alter table(:worth_settings) do
      add :value, :text
    end
  end
end
