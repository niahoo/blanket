defmodule Blanket.Mixfile do
  use Mix.Project

  def project do
    [app: :blanket,
     version: "0.3.1",
     elixir: "~> 1.0",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: "Blanket covers your tables ! Don't loose your ETS tables with Elixir.",
     package: [
       contributors: ["Ludovic Demblans"],
       licenses: ["MIT"],
       links: %{
         "GitHub" => "https://github.com/niahoo/blanket",
         "Hex Docs" => "http://hexdocs.pm/blanket",
         "Don't loose your ETS tables" => "http://steve.vinoski.net/blog/2011/03/23/dont-lose-your-ets-tables/",
         "Erlang inspiration" => "https://github.com/DeadZen/etsgive"
       }
     ],
     deps: deps]
  end

  def application do
    [applications: [:logger],
     mod: {Blanket, []}]
  end

  defp deps do
    [
      {:dogma, git: "https://github.com/lpil/dogma.git", ref: "HEAD", only: :dev},
      {:ex_doc, "~> 0.8.4", only: :dev},
      {:earmark, ">= 0.0.0", only: :dev},
    ]
  end
end
