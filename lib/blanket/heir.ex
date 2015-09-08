defmodule Blanket.Heir do
  @moduledoc """
  This modules describes the generic server for the heirs. Use the `Blanket`
  module to create and interact with the heirs.
  """

  use GenServer
  require Record

  Record.defrecordp :st,
    tab: nil,
    module: nil,
    owner: nil,
    transient: nil,
    mref: nil # monitor reference

  @default_opts [
    transient: false
  ]

  @doc """
  Starts a new heir process. The calling process must own the table, use
  `Blanket.new` to create a table and attach a heir.
  """
  @spec new(module, owner, tab, opts) :: {:ok, pid}
    when  module: atom,
          owner: Blanket.owner,
          tab: :ets.tid,
          opts: Blanket.opts

  def new(module, owner, tab, opts) do
    opts = Keyword.merge(@default_opts, opts)
    conf = [module, owner, tab, opts]
    {:ok, heir_pid} = Supervisor.start_child(Blanket.Supervisor, conf)
    # Now this is tricky. The client process is the current owner of the table.
    # Typically, the process calling Heir.new/3 is not the GenServer that will
    # own the table. It's the process that starts the gen_server.
    # So, we give the table to the heir, and the heir will give it to the
    # GenServer
    true = :ets.give_away(tab, heir_pid, :INIT)
    {:ok, heir_pid}
  end

  @doc false
  def start_link(module, owner, tab, opts) do
    # we build the state out of the GenServer process. That's not a problem.
    state = st(
      tab: tab,
      module: module,
      owner: owner,
      transient: Keyword.get(opts, :transient, false)
    )
    GenServer.start_link(__MODULE__, [state])
  end

  # -- Server side -----------------------------------------------------------

  def init([state]) do
    # Here we do nothing more. In Heir.new, the Heir process is given the table,
    # so we will receive a ETS-TRANSFER in handle_info, tagged with :INIT,
    # where the give_away to the real owner will happen
    {:ok, state}
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_call(_msg, _from, state) do
    {:noreply, state, :hibernate}
  end

  def handle_info({:'ETS-TRANSFER', tab, _, :INIT}, state=st(tab: tab)) do
    # We are receiving the table after its creation. We will fetch the owner
    # pid and give it the table ownership ; after setting ourselves as the heir
    :ets.setopts(tab, {:heir, self, :blanket_heir})
    handle_transfer(state)
  end

  def handle_info({:DOWN, mref, :process, _, :normal}, state=st(mref: mref, transient: true)) do
    # If we receive a 'DOWN' message with the current mref *before* we receive
    # the ETS-TRANSFER, and the reason is :normal AND we have transient: true as
    # an option, we can just die
    {:stop, :normal, state}
  end

  def handle_info({:'ETS-TRANSFER', tab, _, :blanket_heir},
      state=st(tab: tab, transient: true, mref: mref)) do
    # We are receiving a transfer before a 'DOWN' message and we have the option
    # transient: true. We will wait for the 'DOWN' message
    receive do
      {:DOWN, ^mref, :process, _, :normal} -> {:stop, :normal, state}
      {:DOWN, ^mref, :process, _, _other}  -> handle_transfer(state)
    end
  end

  def handle_info({:'ETS-TRANSFER', tab, _, :blanket_heir},
      state=st(tab: tab)) do
    handle_transfer(state)
  end

  def handle_info(_info, state) do
    {:noreply, state, :hibernate}
  end

  defp handle_transfer(state=st(tab: tab)) do
    owner_pid = get_owner_pid(state)
    state = st(state, mref: Process.monitor(owner_pid))
    :ets.give_away(tab, owner_pid, :blanket_giveaway)
    {:noreply, state, :hibernate}
  end

  # this will wait forever, so the client must be sure that the owner process
  # will be restarted (or call Heir.abandon_table)
  defp get_owner_pid(st(module: module, owner: owner)=state) do
    case module.get_owner_pid(owner) do
      pid when is_pid(pid) ->
        pid
      _otherwise ->
        :timer.sleep(1)
        get_owner_pid(state)
    end
  end

end
