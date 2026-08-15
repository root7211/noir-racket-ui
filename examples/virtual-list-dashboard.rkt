#lang noir/ui

;; Fixed-capacity virtual list fixture. All eight row nodes, glyph cells and
;; layout slots exist at compile time; only the first three row slots belong to
;; the initial viewport plan.
(noir-app
 (state [refresh-count 0])
 (action refresh-list (set refresh-count (+ refresh-count 1)))

 (column #:id virtual-dashboard #:gap 12 #:padding 24 #:background dark
   (text #:id title "NOIR VIRTUAL LIST")
   (text #:id refresh-count #:dynamic refresh-count #:max-chars 3)
   (virtual-list #:id telemetry-list
                 #:capacity 8
                 #:visible-rows 3
                 #:row-height 28
                 #:max-chars 8
     (row-template ((node-aa "NODE AAA")
                    (node-bb "NODE BBB")
                    (node-cc "NODE CCC")
                    (node-dd "NODE DDD")
                    (node-ee "NODE EEE")
                    (node-ff "NODE FFF")
                    (node-gg "NODE GGG")
                    (node-hh "NODE HHH"))))
   (button #:id refresh-list-button "REFRESH" #:on refresh-list)))
