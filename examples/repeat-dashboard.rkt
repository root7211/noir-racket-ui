#lang noir/ui

;; 固定数据表是 macro input，而不是 runtime list。每一行均在 expand time 复制 metric-card
;; 模板，生成稳定 core-0/core-1/... namespace 与各自固定 dynamic glyph slots。
(noir-app
 (state
  [core0 11]
  [core1 24]
  [core2 37]
  [core3 52])

 (action refresh-core0
  (set core0 (+ core0 10)))

 (column #:id cpu-dashboard #:gap 16 #:padding 24 #:background dark
   (text #:id cpu-title "NOIR STATIC CPU MONITOR")

   (row #:id cpu-metrics #:gap 8
     (repeat/ui ((card state label)
                 (core-0 core0 "CORE A")
                 (core-1 core1 "CORE B")
                 (core-2 core2 "CORE C")
                 (core-3 core3 "CORE D"))
       (metric-card #:id card #:label label #:dynamic state #:max-chars 3 #:gap 4 #:padding 6)))

   (row #:id cpu-actions #:gap 12
     (control-button #:id refresh-core0-button
                     #:label "REFRESH CPU 0" #:on refresh-core0 #:width 180)))
)
