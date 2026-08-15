#lang noir/ui

;; 三个独立状态域：两个 text-run 和一个只更新固定 instance slot 的 progress bar。
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
   ;; 两层 clip：外层 progress-shell 与内层 progress-layer 的有效裁剪交集必须在宏展开期确定。
   ;; 三个错开的不透明 tooltip 令 progress 差集产生 3 个 fragment；超过 budget=2 后应退化为完整 lower range。
   (stack #:id progress-shell #:clip #t
     (stack #:id progress-layer #:clip #t
       (progress #:id throughput #:dynamic progress #:max 100)
       (overlay #:id tooltip-a #:opacity 1.0 #:width 120 #:x 0 #:z 10)
       (overlay #:id tooltip-b #:opacity 1.0 #:width 120 #:x 180 #:z 11)
       (overlay #:id tooltip-c #:opacity 1.0 #:width 120 #:x 360 #:z 12)))
   (row #:id actions #:gap 12
     (button #:id refresh-fps-button "FPS: 60 → 144" #:on refresh-fps)
     (button #:id refresh-latency-button "Latency: 8 → 15" #:on refresh-latency)
     (button #:id advance-progress-button "Progress: 40 → 72" #:on advance-progress))))
