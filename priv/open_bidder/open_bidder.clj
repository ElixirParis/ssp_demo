;(import '(com.google.openbidder BidRequest))
(require '[clojure-erlastic.core :refer [run-server log]])

(run-server
  (fn [init] {})
  (fn [req state] 
    ;; todo real google query
    [:reply {:bid 3} state]))
