defmodule Worth.Skill.Validator do
  @valid_name_regex ~r/^[a-z0-9][a-z0-9-]{0,63}$/
  @max_name_length 64
  @max_description_length 1024
  @valid_entry_types ~w(outcome event decision observation hypothesis note session_summary conversation_turn archived)

  def validate(skill) when is_map(skill) do
    errors = []

    errors = validate_name(skill.name, errors)
    errors = validate_description(skill.description, errors)
    errors = validate_loading(skill.loading, errors)
    errors = validate_trust_level(skill.trust_level, errors)
    errors = validate_body(skill.body, errors)

    if errors == [] do
      {:ok, skill}
    else
      {:error, errors}
    end
  end

  def validate(_), do: {:error, ["Invalid skill structure"]}

  def validate_file(path) do
    case Worth.Skill.Parser.parse_file(path) do
      {:ok, skill} -> validate(skill)
      error -> error
    end
  end

  defp validate_name(nil, errors), do: ["name is required" | errors]
  defp validate_name(name, errors) when not is_binary(name), do: ["name must be a string" | errors]

  defp validate_name(name, errors) do
    cond do
      String.length(name) > @max_name_length ->
        ["name must be at most #{@max_name_length} characters" | errors]

      not Regex.match?(@valid_name_regex, name) ->
        ["name must be lowercase alphanumeric with hyphens, starting with a letter or digit" | errors]

      true ->
        errors
    end
  end

  defp validate_description(nil, errors), do: ["description is required" | errors]
  defp validate_description(desc, errors) when not is_binary(desc), do: ["description must be a string" | errors]

  defp validate_description(desc, errors) do
    if String.length(desc) > @max_description_length do
      ["description must be at most #{@max_description_length} characters" | errors]
    else
      errors
    end
  end

  defp validate_loading(:always, errors), do: errors
  defp validate_loading(:on_demand, errors), do: errors
  defp validate_loading({:trigger, _}, errors), do: errors
  defp validate_loading(_, errors), do: ["loading must be :always, :on_demand, or {:trigger, event}" | errors]

  defp validate_trust_level(level, errors) when level in [:core, :installed, :learned, :unverified], do: errors
  defp validate_trust_level(_, errors), do: ["trust_level must be :core, :installed, :learned, or :unverified" | errors]

  defp validate_body(nil, errors), do: ["body is required" | errors]

  defp validate_body(body, errors) when is_binary(body) do
    if String.trim(body) == "" do
      ["body must not be empty" | errors]
    else
      errors
    end
  end

  defp validate_body(_, errors), do: ["body must be a string" | errors]
end
