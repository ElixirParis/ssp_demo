use Mix.Config

config :ssp_demo, bidders: [
  %{mod: AdExchange1, name: AdExchange1, conf: %{}, nb_per_ms: {3,500}, max_q: 10},
  %{mod: DSP1, name: DSP1, conf: %{}, nb_per_ms: {3,500}, max_q: 10},
  %{mod: DSP2, name: DSP2, conf: %{}, nb_per_ms: {3,500}, max_q: 10}
]

config :ssp_demo, bid_config: %{
  slots: %{
    "upright"=>%{width: 100, height: 100, params: [:no_expandingup]},
    "bg"=>%{width: 100, height: 100, params: [:no_usertargeting]}
  },
  verticals: [{"computer",0.2},{"finance",0.1}],
  excluded_agencies: ["247 Real Media"],
  excluded_rich_media: ["Pointroll"],
  min_cpm: 6
}
