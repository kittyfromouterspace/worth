defmodule Worth.Sync.Adapter do
  @moduledoc """
  Behaviour for sync engine plugins.

  Worth calls these callbacks to start/stop the sync engine and query status.
  The sync engine communicates with Worth through the opts passed to `start/1`
  (repo module, settings callbacks, pubsub name) — it should not import
  any `Worth.*` modules directly.

  Worth emits PubSub events that sync plugins can subscribe to:

    * `worth_entry_change` — `{:entry, :create | :update | :delete, entry_map}`
    * `worth_graph_change` — `{:graph, :create | :update | :delete, change_map}`
    * `worth_file_change` — `{:file, workspace_id, relative_path, event_atom}`

  ## Usage

  To add sync to Worth, depend on a sync plugin and configure it:

      config :worth, :sync_adapter, MySyncPlugin.Adapter

  Worth will call `MySyncPlugin.Adapter.start/1` at boot with the required opts.
  """

  @doc "Start the sync engine. Receives opts with `:repo`, `:pubsub`, `:settings_get`, `:settings_put`, `:settings_delete`."
  @callback start(opts :: keyword()) :: {:ok, pid()} | {:error, term()}

  @doc "Stop the sync engine gracefully."
  @callback stop() :: :ok

  @doc "Called when a recollect entry is created or updated locally."
  @callback on_entry_change(entry :: map()) :: :ok

  @doc "Called when a recollect entity or relation changes locally."
  @callback on_graph_change(change :: map()) :: :ok

  @doc "Called when a workspace file changes (create, modify, delete, rename)."
  @callback on_file_change(workspace_id :: String.t(), relative :: String.t(), event :: atom()) :: :ok

  @doc "True if cloud sync is active and connected."
  @callback connected?() :: boolean()

  @doc "List of workspace IDs that are currently syncing on this device."
  @callback synced_workspaces() :: [String.t()]

  @doc "Return the configured server endpoint URL, or nil if not configured."
  @callback endpoint() :: String.t() | nil
end
