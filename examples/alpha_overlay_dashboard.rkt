#lang noir/ui

;; 与 opaque 实验同构，但 overlay 是 alpha；compiler 不得消除 progress 或任何 clip stack range。
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

 (column #:id dashboard #:gap 16 #:padding 24 #:background dark
   (text #:id title "NOIR CAUSAL GPU DASHBOARD")
   (row #:id metrics #:gap 12
     (text #:id fps #:dynamic frame-rate #:max-chars 3)
     (text #:id latency #:dynamic latency-ms #:max-chars 3))
   (stack #:id progress-shell #:clip #t
     (stack #:id progress-layer #:clip #t
       (progress #:id throughput #:dynamic progress #:max 100)
       (overlay #:id progress-alert #:opacity 0.42 #:z 10)))
   (row #:id actions #:gap 12
     (button #:id refresh-fps-button "FPS: 60 → 144" #:on refresh-fps)
     (button #:id refresh-latency-button "Latency: 8 → 15" #:on refresh-latency)
     (button #:id advance-progress-button "Progress: 40 → 72" #:on advance-progress))))
