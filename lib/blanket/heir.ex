defmodule Blanket.Heir do
  use GenServer
  # require Logger

  # x @todo seems we do not need the tab in the GenServer state. We could use it
  # to match on the table if someone (for one reason) decide to set a Heir
  # instance to be the heir of another table.

  def start_link(tab_name, tab_opts, get_pid) do
    GenServer.start_link(__MODULE__, [tab_name, tab_opts, get_pid])
  end

  # -- Server side -----------------------------------------------------------

  require Record
  Record.defrecordp :heir, tab: nil, module: nil, owner: nil

  def init([module, owner, tab]) do
    state = heir(tab: tab, module: module, owner: owner)
    {:ok, state}
    # Here we do nothing more. In Heir.new, the Heir process is given the table,
    # so we will receive a ETS-TRANSFER in handle_info, tagged with :bootstrap,
    # where the give_away to the real owner will happen
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_call(_msg, _from, state) do
    {:noreply, state, :hibernate}
  end

  def handle_info({:'ETS-TRANSFER', tab, _starter_pid, :bootstrap}, state) do
    # We are receiving the table after its creation. We will fetch the owner
    # pid and give it the table ownership ; after setting ourselves as the heir
    :ets.setopts(tab, {:heir, self, :blanket_heir})
    give_away_table(tab, state)
    {:noreply, state, :hibernate}
  end

  def handle_info({:'ETS-TRANSFER', tab, _dead_owner_pid, :blanket_heir}, state) do
    give_away_table(tab, state)
    {:noreply, state, :hibernate}
  end

  def handle_info(_info, state) do
    {:noreply, state, :hibernate}
  end

  defp give_away_table(tab, state) do
    owner_pid = get_owner_pid(state)
    :ets.give_away(tab, owner_pid, :blanket_giveaway)
  end

  # this will wait forever, so the client must be sure that the owner process
  # will be restarted (or call Heir.abandon_table)
  defp get_owner_pid(heir(module: module, owner: owner)=state) do
    case module.get_owner_pid(owner) do
      pid when is_pid(pid) -> pid
      _ ->
          :timer.sleep(1)
          get_owner_pid(state)
    end
  end

end
