#lang noir/ui

;; Negative fixture: writes are independent, but both action targets occupy the
;; same compiler tile. Fusion admission must reject with tile-overlap while the
;; ordinary winner-write executor remains semantically executable.
(noir-app
 (state [frame-rate 60]
        [latency-ms 8])
 (action refresh-fps (set frame-rate (+ frame-rate 84)))
 (action refresh-latency (set latency-ms (+ latency-ms 7)))
 (column #:id rejected-root #:gap 12 #:padding 24 #:background dark
   (text #:id title "NOIR FUSION REJECT")
   (stack #:id same-tile-metrics
     (text #:id fps #:x 0 #:y 0 #:dynamic frame-rate #:max-chars 3)
     (text #:id latency #:x 100 #:y 0 #:dynamic latency-ms #:max-chars 3))
   (multi-action-event #:id unsafe-refresh
                       #:actions (refresh-fps refresh-latency)
                       "UNSAFE REFRESH")))
