#lang noir/ui

;; Realtime monitor v1 exercises the frozen long-list ABI with a different update
;; pattern from log-browser: fixed telemetry columns, numeric refresh values, visible
;; and arena-only updates, selected-row detail, and the same fixed row activation path.
(noir-app
 (font-asset #:manifest "assets/fontc/noir-desktop-sans-18/manifest.json"
             #:atlas "assets/fontc/noir-desktop-sans-18/atlas.r8")
 (theme noir-monitor
   (color canvas "#0B1018" surface "#141D2A" panel "#1B2636" header "#172B45"
          accent "#2CB67D" danger "#E85D75" text "#F4F7FB" muted "#91A0B8")
   (space xs 4 sm 8 md 12 lg 16 xl 24 page 32)
   (type caption 13 body 15 label 16 title 28 display 36)
   (radius control 6 card 10 panel 14 overlay 18))
 (state [monitor-detail-damage 0])
 (action open-monitor-detail (set monitor-detail-damage (+ monitor-detail-damage 1)))
 (list-navigation #:id monitor-navigation #:for telemetry-grid #:scrollbar monitor-scrollbar)
 ;; This application-level plan reuses the existing detail/color/append protocol.
 ;; The record itself is a telemetry schema: STATE HOST CPU MEM NET LAT JIT.
 (log-browser #:id telemetry-dashboard #:for telemetry-grid #:detail monitor-detail
   #:append ((9997 "WARN TAILA 090 700 080 020 010")
             (9998 "ERROR TAILB 097 882 091 024 021")
             (9999 "DEBUG TAILC 011 101 004 003 001")))
 (column #:id monitor-shell #:gap (theme-space sm) #:padding (theme-space lg)
         #:background (theme-color canvas) #:radius (theme-radius panel)
   (stack #:id monitor-app-bar #:height 34 #:background (theme-color header)
     (text #:id monitor-title #:height 34 #:background (theme-color header)
           #:font-face noir-desktop-sans-18 "REALTIME MONITOR TABLE"))
   (stack #:id monitor-column-header #:height 24 #:background (theme-color surface)
     (text #:id monitor-columns #:height 24 #:background (theme-color surface)
           #:font-face noir-desktop-sans-18 "STATE HOST CPU MEM NET LAT JIT"))
   (stack #:id monitor-list-shell #:height 84 #:clip true #:background (theme-color panel)
     (virtual-list #:id telemetry-grid
                   #:logical-capacity 10000
                   #:physical-slots 4
                   #:visible-rows 3
                   #:row-height 28
                   #:max-chars 36
       (data-register-table #:id telemetry-registers #:seed "NOMINAL ALPHA LOW MID LOW FAST LOW"
         ;; Two visible records exercise GPU glyph writes; one far record proves arena-only refresh.
         (data-update-batch #:id bootstrap-telemetry
           ((0 "WARN ALPHA 042 731 018 012 005")
            (1 "ERROR BRAVO 081 654 073 019 014")
            (5000 "DEBUG CHARLIE 013 224 009 004 002"))))
       (on-activate open-monitor-detail)
       (row-template ((telemetry-row-a "NOMINAL ALPHA LOW MID LOW FAST LOW")
                      (telemetry-row-b "NOMINAL ALPHA LOW MID LOW FAST LOW")
                      (telemetry-row-c "NOMINAL ALPHA LOW MID LOW FAST LOW")
                      (telemetry-row-d "NOMINAL ALPHA LOW MID LOW FAST LOW"))))
     (scrollbar #:id monitor-scrollbar #:for telemetry-grid
                #:x 554 #:y 0 #:width 12 #:height 84 #:thumb-height 18))
   (stack #:id monitor-detail-panel #:height 34 #:background (theme-color surface)
     (text #:id monitor-detail #:height 34 #:background (theme-color surface)
           #:dynamic monitor-detail-damage #:max-chars 29))
   (stack #:id monitor-refresh-bar #:height 30 #:background (theme-color accent)
     (button #:id refresh-telemetry #:height 30 #:background (theme-color accent)
             "REFRESH BATCH" #:on open-monitor-detail)
     (text #:id refresh-telemetry-label #:height 30 #:background (theme-color accent)
           #:font-face noir-desktop-sans-18 "REFRESH FIXED BATCH"))))
