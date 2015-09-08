defmodule Blanket do
  @moduledoc """
  This is the top module of the Blanket application.
  """

  # -- Application API --------------------------------------------------------

  use Application

  def start(_type, _args) do
    Blanket.Supervisor.start_link
  end

  # Table Owner API -----------------------------------------------------------

  defmacro __using__(_) do
    Blanket.TableOwner.default_owner_defs
  end

  # Heir API ------------------------------------------------------------------


  # The table is created in the calling process, as is called the populate fn,
  # so creation errors are synchronous in the calling process

  def new(module, owner, tab_def, opts \\ [])

  def new(module, owner, tab_def, opts) when is_list(opts) do
    {tab_name, tab_opts} = tab_def
    tab = :ets.new(tab_name, tab_opts)
    {populate, opts} =
      opts
      |> proplist_to_keywords
      |> Keyword.pop(:populate, fn(_) -> :ok end)
    case populate.(tab) do
      :ok -> start_heir(module, owner, tab, opts)
      err ->
          :ets.delete(tab)
          wrap_error(err)
    end
  end

  def new(module, owner, tab_def, populate) when is_function(populate, 1) do
    new(module, owner, tab_def, [populate: populate])
  end

  def receive_table(timeout \\ 5000) do
    receive do
      {:'ETS-TRANSFER', tab, _heir_pid, :blanket_giveaway} ->
        {:ok, tab}
    after
      timeout -> {:error, :ets_transfer_timeout}
    end
  end

  def abandon_table(tab, heir) do
    # The owner must be the process which set options
    true = :ets.setopts(tab, [{:heir, :none}])
    GenServer.call(heir, :stop)
  end

  defp start_heir(module, owner, tab, opts) do
    Blanket.Heir.new(module, owner, tab, opts)
  end

  defp wrap_error({:error, reason}), do: {:error, reason}
  defp wrap_error(err), do: {:error, err}

  defp proplist_to_keywords(opts) do
    opts |> Enum.map(
      fn({k, v}) -> {k, v}
        (k) -> {k, true}
      end
    )
  end

end
