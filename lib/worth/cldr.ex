defmodule Worth.Cldr do
  @moduledoc """
  CLDR backend for `:ex_money` in the Worth host. Worth carries the
  full CLDR locale set (single-machine desktop app, footprint isn't a
  concern); enable additional locales here if they're ever needed for
  display.
  """

  use Cldr,
    locales: ["en"],
    default_locale: "en",
    providers: [Cldr.Number, Money]
end
