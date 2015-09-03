defmodule Blanket.Heir do
  use GenServer

  def new(tab_name, options, get_pid) do
    # The table is created here, in the same process than the caller, so
    # creation errors will pop in the caller process
    tab = :ets.new(tab_name, options)
    heir_conf = [tab_name, options, get_pid]
    {:ok, pid} = Supervisor.start_child(Blanket.Supervisor, heir_conf)
    # now we give the table
    true = :ets.give_away(tab, pid, {:created, self})
    {:ok, tab}
  end

  def start_link(tab_name, options, get_pid) do
    GenServer.start_link(__MODULE__, [tab_name, options, get_pid])
  end

  # --------------

  def init([tab_name, options, get_pid]) do
    {:ok, :state}
  end

end
