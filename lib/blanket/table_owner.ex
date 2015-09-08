defmodule Blanket.TableOwner do
  @moduledoc """
  This module provides the quoted forms for the modules calling `use Blanket`.
  """

  @doc """
  Provides the default functions for a table owner.
  """
  def default_owner_defs do
    quote location: :keep do

      @doc """
      Defined from `use Blanket`. Returns the pid for a given table owner.
      """
      @spec get_owner_pid(Blanket.owner) :: pid
      def get_owner_pid(owner), do: Process.whereis(owner)
      defoverridable [get_owner_pid: 1]

    end
  end

end
