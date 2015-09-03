defmodule Blanket do
  use Application

  def start(_type, _args) do
    _x = Blanket.Supervisor.start_link
  end

end
