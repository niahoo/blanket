defmodule Blanket do
  use Application
  require Logger

  def start(_type, _args) do
    x = Blanket.Supervisor.start_link
    Logger.debug "Blanket started"
    x
  end

  def new_table(name, options, get_pid) do
    Blanket.Heir.new(name, options, get_pid)
  end
end
