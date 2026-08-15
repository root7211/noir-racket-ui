#lang noir/ui

;; 此文件只使用组件层 API；metric-card/control-button 在 #lang 宏展开期内联，
;; runtime Scene 不包含组件对象、virtual tree 或组件 dispatch。
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

 (column #:id component-dashboard #:gap 16 #:padding 24 #:background dark
   (text #:id component-title "NOIR COMPILED COMPONENT DASHBOARD")

   ;; 在 macro expansion 后，两个 metric-card 分别是一个 column，内部含静态 label
   ;; text 与固定容量动态 text-run；因此 shaping、placement 和 glyph patch 仍完全静态。
   (row #:id component-metrics #:gap 12
     (metric-card #:id fps-card #:label "FPS" #:dynamic frame-rate #:max-chars 3)
     (metric-card #:id latency-card #:label "LAT" #:dynamic latency-ms #:max-chars 3))

   (stack #:id component-progress-shell #:clip #t
     (progress #:id component-throughput #:dynamic progress #:max 100)
     (overlay #:id component-tooltip #:opacity 0.7 #:width 160 #:x 180 #:z 10))

   ;; control-button 内联为现有 button primitive，因此 Event Map、pressed/release task、
   ;; Coalesced Batch、tile IDs 和 action patch 继续沿用既有 compiler lowering。
   (row #:id component-actions #:gap 12
     (control-button #:id component-refresh-fps #:label "REFRESH FPS" #:on refresh-fps #:width 140)
     (control-button #:id component-refresh-latency #:label "REFRESH LAT" #:on refresh-latency #:width 140)
     (control-button #:id component-advance-progress #:label "ADVANCE" #:on advance-progress #:width 120)))
)
