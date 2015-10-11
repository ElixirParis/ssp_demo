defmodule SSPDemo.Mixfile do
  use Mix.Project

  def project do
    [app: :ssp_demo,
     version: "0.0.1",
     elixir: "~> 1.1",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps]
  end

  def application do
    [applications: [:logger,:plug,:cowboy,:iex,:poison, :exos,:folsom,:folsomite],
     mod: {SSPDemo.App,[]}]
  end

  defp deps do
    [{:cowboy, "~> 1.0"},
     {:plug, "~> 1.0"},
     {:exos, "~> 1.0.0"},
     {:poison, "~> 1.5.0"},
     {:folsomite, github: "campanja/folsomite"}]
  end
end
