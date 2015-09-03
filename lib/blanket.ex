defmodule Blanket do
  use Application
  require Logger

  def start(_type, _args) do
    x = Blanket.Supervisor.start_link
    Logger.debug "Blanket started"
    x
  end

end
