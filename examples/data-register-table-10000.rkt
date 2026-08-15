#lang noir/ui

;; A compact 10,000-row logical data arena. Only four physical row templates are
;; materialized; the compiler must export a compact register artifact instead of
;; expanding per-row labels or per-viewport transitions.
(noir-app
 (state [tick 0])
 (action refresh-tick (set tick (+ tick 1)))
 (list-navigation #:id telemetry-navigation #:for telemetry-registers #:scrollbar telemetry-scrollbar)
 (column #:id data-register-dashboard #:gap 10 #:padding 16 #:background dark
   (text #:id title "REGISTER LIST")
   ;; `scrollbar` is a separate v1 artifact. It references the frozen list ID,
   ;; while track/thumb geometry and the thumb Instance Buffer address remain static.
   (stack #:id telemetry-list-shell #:height 84 #:clip true
     (virtual-list #:id telemetry-registers
                   #:logical-capacity 10000
                   #:physical-slots 4
                   #:visible-rows 3
                   #:row-height 28
                   #:max-chars 10
       (data-register-table #:id telemetry-data #:seed "ROW VALUE"
         (data-update-batch #:id bootstrap-telemetry
           ((0 "LIVE ZERO") (1 "LIVE ONE") (2 "LIVE TWO"))))
       (on-activate refresh-tick)
       (row-template ((register-a "ROW VALUE")
                      (register-b "ROW VALUE")
                      (register-c "ROW VALUE")
                      (register-d "ROW VALUE"))))
     (scrollbar #:id telemetry-scrollbar #:for telemetry-registers
                #:x 554 #:y 0 #:width 12 #:height 84 #:thumb-height 18))
   (text #:id tick #:dynamic tick #:max-chars 3)
   (button #:id refresh-registers "REFRESH" #:on refresh-tick)))
