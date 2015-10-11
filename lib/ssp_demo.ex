defmodule SSPDemo.App do
  use Application
  import Supervisor.Spec

  def start(_,_) do
    Supervisor.start_link([
      supervisor(SSPDemo.App.BidderCallerSup,[],[]),
      worker(SSPDemo.Reporter,[],[]),
      Plug.Adapters.Cowboy.child_spec(:http,SSPDemo.HTTP,[],port: 7321)
    ], strategy: :one_for_one)
  end

  defmodule BidderCallerSup do
    import Supervisor.Spec
    def start_link do
      Supervisor.start_link([
        worker(SSPDemo.Config,[],[]),
        supervisor(SSPDemo.App.BidderSup,[],[]),
        supervisor(SSPDemo.CallerSup,[],[])
      ] , strategy: :one_for_one)
    end
  end

  defmodule BidderSup do
    import Supervisor.Spec
    def start_link do
      bidders = Application.get_env(:ssp_demo,:bidders)
      Supervisor.start_link(for %{name: name}=bidder<-bidders do
        worker(SSPDemo.Throttler,[bidder],id: name)
      end, strategy: :one_for_one)
    end
  end
end

defmodule SSPDemo.Throttler do
  use GenServer

  defmodule TimeRing do
    defstruct set: {}, oldest_idx: 0, m: 5, n: 1
    def now, do: :erlang.system_time(:milli_seconds)
    def new(m,n),do: %TimeRing{set: :erlang.make_tuple(m,now),m: m, n: n, oldest_idx: 0}
    def next(%{set: s,oldest_idx: idx,n: n, m: m}=ring) do
      wait = max(0,n - (now - elem(s,idx)))
      ring = %{ring| set: put_elem(s,idx,now+wait), oldest_idx: if(idx+1>m-1, do: 0, else: idx+1)}
      {wait,ring}
    end
  end

  def start_link(bidder), do:
    GenServer.start_link(__MODULE__, bidder, name: bidder.name)

  def init(%{mod: mod,conf: conf,nb_per_ms: {m,n}, max_q: maxqlen}) do
    {:ok,pid} = mod.start_link(conf)
    {:ok,%{pid: pid, tr: TimeRing.new(m,n), maxqlen: maxqlen, qlen: 0, q: :queue.new}}
  end
  def handle_call(_req,_reply_to,%{maxqlen: qlen, qlen: qlen}=state) do
    IO.puts "Bidder #{elem(Process.info(self,:registered_name),1)} overloaded, drop request"
    # TODO put dropped query into folsom
    {:noreply,state}
  end
  def handle_call(req,reply_to,%{q: q,tr: timering, qlen: qlen}=state) do
    {wait,timering} = TimeRing.next(timering)
    {:noreply,%{state| qlen: qlen+1, q: :queue.in({req,reply_to},q), tr: timering},wait}
  end
  def handle_info(:timeout,%{pid: pid, q: q, qlen: qlen}=state) do
    {{:value, {req,reply_to}}, q} = :queue.out(q)
    spawn(fn-> GenServer.reply(reply_to,GenServer.call(pid,req)) end)
    {:noreply,%{state|q: q, qlen: qlen-1}}
  end
end

defmodule SSPDemo.Bidder do
  use Behaviour 
  defcallback start_link(conf::any)
  defcallback map_request(SSPDemo.BidRequest.t) :: any
  defcallback use_bidder(SSPDemo.BidRequest.t) :: boolean

  defmacro __using__(_opts) do
    quote do
      @behaviour SSPDemo.Bidder
      use GenServer
      def start_link(conf) do
        GenServer.start_link(__MODULE__,conf,[])
      end
      def map_request(req), do: req
      def use_bidder(req), do: true
    end
  end
end

defmodule SSPDemo.BidRequest do
  defstruct ip: nil, user_agent: nil, language: "en", verticals: [], geo: nil,  
            min_cpm: 0, excluded_agencies: [], excluded_rich_media: [],
            slot_width: 0, slot_height: 0, parameters: []
end

defmodule SSPDemo.BidResponse do
  defstruct bid: 0, html: ""
end

defmodule SSPDemo.Config do
  def start_link, do:
    Agent.start_link(fn -> Application.get_env(:ssp_demo,:bid_config) end, name: __MODULE__)
  def update(conf), do: Agent.update(__MODULE__, fn _->conf end)
  def get, do: Agent.get(__MODULE__, &(&1))
end

defmodule SSPDemo.CallerSup do
  def start_link, do: 
    Task.Supervisor.start_link(name: __MODULE__, restart: :transient)
  def request(bidder_id,bidrequest) do
    Task.Supervisor.start_child(__MODULE__, fn ->
      GenServer.call(bidder_id,bidrequest)
    end)
  end
end

defmodule SSPDemo.Reporter do
  use GenServer
  def start_link, do:
    GenServer.start_link(__MODULE__,[]) 

  def handle_cast(_log,state) do
    ## TODO folsom put metric
    {:noreply,state}
  end
end

defmodule SSPDemo do
  def auction(ip,user_agent,language,slot_id) do
    conf = SSPDemo.Config.get
    request = %SSPDemo.BidRequest{} ## TODO complete with user data + conf
    response = Application.get_env(:ssp_demo,:bidders)
      |> Enum.filter(& &1.mod.use_bidder(request))
      |> Enum.map(&SSPDemo.CallerSup.request(&1.name,request))
      |> Enum.map(&Task.yield(&1,100))
      |> Enum.filter(& !is_nil(&1))
      |> Enum.sort_by(& &1.bid)
      |> List.first
    GenServer.cast SSPDemo.Reporter, response
    response
  end
end

defmodule SSPDemo.HTTP do
  use Plug.Router
  plug :match
  plug :dispatch

  get "/ad/:slot" do
    # todo, get headers to fill user agent and language
    response = SSPDemo.auction(conn.remote_ip,"","fr",slot)
    conn |> put_resp_content_type("application/json")
         |> send_resp(200, Poison.encode(response))
  end

  match _ do
    send_resp(conn, 404, "oops")
  end
end
