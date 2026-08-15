#lang noir/ui

;; Static multi-action fusion fixture. The three actions write disjoint state/GPU
;; ranges and own separate action-aware tiles. The compiler must admit fusion only
;; after proving write, tile, packet-scope and release-order invariants.
(noir-app
 (state
  [frame-rate 60]
  [latency-ms 8]
  [progress 40])

 (action refresh-fps
  (set frame-rate (+ frame-rate 84)))
 (action refresh-latency
  (set latency-ms (+ latency-ms 7)))
 (action advance-progress
  (set progress (+ progress 32)))

 (column #:id multi-action-dashboard #:gap 16 #:padding 24 #:background dark
   (text #:id title "NOIR MULTI ACTION FUSION")
   (row #:id metrics #:gap 12
     (text #:id fps #:dynamic frame-rate #:max-chars 3)
     (text #:id latency #:dynamic latency-ms #:max-chars 3))
   (stack #:id progress-shell #:clip #t
     (stack #:id progress-layer #:clip #t
       (progress #:id throughput #:dynamic progress #:max 100)
       (overlay #:id tooltip-a #:opacity 1.0 #:width 120 #:x 0 #:z 10)
       (overlay #:id tooltip-b #:opacity 1.0 #:width 120 #:x 180 #:z 11)
       (overlay #:id tooltip-c #:opacity 1.0 #:width 120 #:x 360 #:z 12)))
   (multi-action-event #:id refresh-all
                       #:actions (refresh-fps refresh-latency advance-progress)
                       "REFRESH ALL")))
