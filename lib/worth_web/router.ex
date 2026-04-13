defmodule WorthWeb.Router do
  @moduledoc """
  Routes for the Worth web UI.
  """

  use WorthWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WorthWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", WorthWeb do
    pipe_through :browser

    live "/", ChatLive, :index
  end
end
