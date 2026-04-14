defmodule Worth.Orchestration.ExperimentServiceTest do
  use Worth.DataCase, async: true

  alias Worth.Orchestration.ExperimentService

  @valid_attrs %{
    name: "Test Experiment",
    description: "A test experiment",
    strategies: ["default", "stigmergy"],
    prompts: ["Solve problem A", "Solve problem B"],
    repetitions: 2
  }

  describe "create/1" do
    test "creates an experiment with valid attrs" do
      assert {:ok, experiment} = ExperimentService.create(@valid_attrs)
      assert experiment.name == "Test Experiment"
      assert experiment.strategies == ["default", "stigmergy"]
      assert experiment.prompts == ["Solve problem A", "Solve problem B"]
      assert experiment.repetitions == 2
      assert experiment.status == "pending"
    end

    test "fails without required fields" do
      assert {:error, changeset} = ExperimentService.create(%{})
      assert changeset.errors[:name]
      assert changeset.errors[:strategies]
      assert changeset.errors[:prompts]
    end

    test "fails with empty strategies" do
      attrs = Map.put(@valid_attrs, :strategies, [])
      assert {:error, changeset} = ExperimentService.create(attrs)
      assert changeset.errors[:strategies]
    end

    test "fails with empty prompts" do
      attrs = Map.put(@valid_attrs, :prompts, [])
      assert {:error, changeset} = ExperimentService.create(attrs)
      assert changeset.errors[:prompts]
    end

    test "fails with zero repetitions" do
      attrs = Map.put(@valid_attrs, :repetitions, 0)
      assert {:error, changeset} = ExperimentService.create(attrs)
      assert changeset.errors[:repetitions]
    end
  end

  describe "list/0" do
    test "returns empty list when no experiments" do
      assert ExperimentService.list() == []
    end

    test "returns experiments ordered by inserted_at desc" do
      {:ok, _first} = ExperimentService.create(%{@valid_attrs | name: "First"})
      {:ok, second} = ExperimentService.create(%{@valid_attrs | name: "Second"})

      results = ExperimentService.list()
      assert length(results) == 2
      assert hd(results).id == second.id
    end
  end

  describe "get!/1" do
    test "returns the experiment with the given id" do
      {:ok, experiment} = ExperimentService.create(@valid_attrs)
      assert ExperimentService.get!(experiment.id).id == experiment.id
    end

    test "raises when experiment not found" do
      assert_raise Ecto.NoResultsError, fn ->
        ExperimentService.get!(Ecto.UUID.generate())
      end
    end
  end

  describe "run_experiment/1" do
    test "sets experiment status to running" do
      {:ok, experiment} = ExperimentService.create(@valid_attrs)
      assert {:ok, running} = ExperimentService.run_experiment(experiment.id)
      assert running.status == "running"
    end
  end
end
