defmodule Worth.Cloud.Client do
  @moduledoc """
  HTTP client for Homunculus cloud API.

  Handles device provisioning, workspace subscriptions, and write-path sync.
  Device token is stored in Worth.Settings as an encrypted secret.
  """

  require Logger

  @setting_key "cloud_device_token"
  @endpoint_setting "cloud_endpoint"

  def configured? do
    case get_token() do
      {:ok, _} -> true
      _ -> false
    end
  end

  def get_endpoint do
    Worth.Config.get([:cloud, :endpoint], "https://getahead.now")
  end

  def get_token do
    Worth.Settings.get_preference(@setting_key) ||
      Worth.Settings.get(@setting_key)
  end

  def save_token(token) do
    Worth.Settings.put(@setting_key, token, "secret")
  end

  def clear_token do
    Worth.Settings.delete(@setting_key)
  end

  def create_challenge(device_name, device_type) do
    endpoint = get_endpoint()

    "#{endpoint}/api/v1/device/challenge"
    |> Req.post!(json: %{device_name: device_name, device_type: device_type})
    |> case do
      %{status: 200, body: body} -> {:ok, body}
      %{status: status, body: body} -> {:error, {status, body}}
    end
  end

  def poll_challenge(challenge_id) do
    endpoint = get_endpoint()

    "#{endpoint}/api/v1/device/challenge/#{challenge_id}"
    |> Req.get!()
    |> case do
      %{status: 200, body: %{"status" => "approved", "device_token" => token}} ->
        save_token(token)
        {:ok, :approved}

      %{status: 200, body: %{"status" => status}} ->
        {:ok, String.to_atom(status)}

      %{status: status, body: body} ->
        {:error, {status, body}}
    end
  end

  def list_workspaces do
    with {:ok, token} <- get_token(),
         endpoint = get_endpoint(),
         %{status: 200, body: body} <-
           Req.get!(
             "#{endpoint}/api/v1/sync/workspaces",
             headers: [{"authorization", "Bearer #{token}"}]
           ) do
      {:ok, body["workspaces"]}
    else
      {:error, reason} -> {:error, reason}
      %{status: status, body: body} -> {:error, {status, body}}
    end
  end

  def subscribe_workspace(workspace_id) do
    with {:ok, token} <- get_token(),
         endpoint = get_endpoint(),
         %{status: 200, body: body} <-
           Req.post!(
             "#{endpoint}/api/v1/sync/subscribe",
             json: %{workspace_id: workspace_id},
             headers: [{"authorization", "Bearer #{token}"}]
           ) do
      {:ok, body}
    else
      {:error, reason} -> {:error, reason}
      %{status: status, body: body} -> {:error, {status, body}}
    end
  end

  def unsubscribe_workspace(workspace_id) do
    with {:ok, token} <- get_token(),
         endpoint = get_endpoint(),
         %{status: 200, body: body} <-
           Req.post!(
             "#{endpoint}/api/v1/sync/unsubscribe",
             json: %{workspace_id: workspace_id},
             headers: [{"authorization", "Bearer #{token}"}]
           ) do
      {:ok, body}
    else
      {:error, reason} -> {:error, reason}
      %{status: status, body: body} -> {:error, {status, body}}
    end
  end

  def mutate(transaction) do
    with {:ok, token} <- get_token(),
         endpoint = get_endpoint(),
         %{status: 200, body: body} <-
           Req.post!(
             "#{endpoint}/api/v1/sync/mutate",
             json: %{transaction: transaction},
             headers: [{"authorization", "Bearer #{token}"}]
           ) do
      {:ok, body}
    else
      {:error, reason} -> {:error, reason}
      %{status: status, body: body} -> {:error, {status, body}}
    end
  end
end
