#lang noir/ui

(noir-app
 (state [tick 0])
 (action refresh-tick (set tick (+ tick 1)))
 (stack #:id recycling-root #:width 640 #:height 360 #:gap 10
   (text #:id recycling-title "RING LIST")
   (virtual-list #:id telemetry-ring
                 #:logical-capacity 12
                 #:physical-slots 4
                 #:visible-rows 3
                 #:row-height 28
                 #:max-chars 10
     (data-table ((sample-aa "SAMPLE AA")
                  (sample-bb "SAMPLE BB")
                  (sample-cc "SAMPLE CC")
                  (sample-dd "SAMPLE DD")
                  (sample-ee "SAMPLE EE")
                  (sample-ff "SAMPLE FF")
                  (sample-gg "SAMPLE GG")
                  (sample-hh "SAMPLE HH")
                  (sample-ii "SAMPLE II")
                  (sample-jj "SAMPLE JJ")
                  (sample-kk "SAMPLE KK")
                  (sample-ll "SAMPLE LL")))
     (row-template ((ring-a "SAMPLE AA")
                    (ring-b "SAMPLE BB")
                    (ring-c "SAMPLE CC")
                    (ring-d "SAMPLE DD"))))
   (text #:id recycling-status #:dynamic tick #:max 999 #:max-chars 3)
   (button #:id recycling-refresh "REFRESH" #:on refresh-tick)))
