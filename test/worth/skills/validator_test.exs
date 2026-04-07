defmodule Worth.Skill.ValidatorTest do
  use ExUnit.Case

  test "validates a valid skill" do
    skill = valid_skill()
    assert {:ok, ^skill} = Worth.Skill.Validator.validate(skill)
  end

  test "rejects missing name" do
    skill = %{valid_skill() | name: nil}
    assert {:error, errors} = Worth.Skill.Validator.validate(skill)
    assert Enum.any?(errors, &String.contains?(&1, "name"))
  end

  test "rejects name with invalid characters" do
    skill = %{valid_skill() | name: "INVALID Name!"}
    assert {:error, errors} = Worth.Skill.Validator.validate(skill)
    assert Enum.any?(errors, &String.contains?(&1, "name"))
  end

  test "rejects name too long" do
    skill = %{valid_skill() | name: String.duplicate("a", 65)}
    assert {:error, errors} = Worth.Skill.Validator.validate(skill)
    assert Enum.any?(errors, &String.contains?(&1, "name"))
  end

  test "accepts valid hyphenated name" do
    skill = %{valid_skill() | name: "my-awesome-skill"}
    assert {:ok, _} = Worth.Skill.Validator.validate(skill)
  end

  test "rejects missing description" do
    skill = %{valid_skill() | description: nil}
    assert {:error, errors} = Worth.Skill.Validator.validate(skill)
    assert Enum.any?(errors, &String.contains?(&1, "description"))
  end

  test "rejects empty body" do
    skill = %{valid_skill() | body: "   "}
    assert {:error, errors} = Worth.Skill.Validator.validate(skill)
    assert Enum.any?(errors, &String.contains?(&1, "body"))
  end

  test "rejects invalid trust level" do
    skill = %{valid_skill() | trust_level: :unknown}
    assert {:error, errors} = Worth.Skill.Validator.validate(skill)
    assert Enum.any?(errors, &String.contains?(&1, "trust_level"))
  end

  defp valid_skill do
    %{
      name: "test-skill",
      description: "A test skill",
      loading: :always,
      trust_level: :core,
      body: "Some instructions"
    }
  end
end
