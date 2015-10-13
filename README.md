# SSPDemo

Plug metrics into Riemann with config `./riemann.config`
which compute rates and send them to influxdb.
Use chronograph to show a graph querying influxdb rate timeseries.

http://127.0.0.1:10000/graph?d0=riemann&d1=riemann&d2=riemann&d3=riemann&d4=riemann&f0.0=value&f1.0=value&f2.0=value&f3.0=value&f4.0=value&m0=bid_Elixir.AdExchange1_rate&m1=bid_Elixir.DSP1_rate&m2=bid_Elixir.DSP2_rate&m3=auction_fail_rate&m4=auction_success_rate&s0=22&s1=22&s2=22&s3=22&s4=22&tl=now()%20-%2015m

- show diagram
- show code:
  - quick supervision tree
  - throttler
  - query management
  - the bidder protocol and default impl thanks to Elixir

- show fluent query rate management and memory control with
  throttling
- show state related bug in AdExchange1 and config recovery with
  min_cpm: 10
- show random bug in DSP2 and resilience thanks to task transient
  supervision
- show hot reloading removing the bug

Enjoy !
