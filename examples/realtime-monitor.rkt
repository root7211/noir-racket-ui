#lang noir/ui

;; Realtime monitor v1 exercises the frozen long-list ABI with a different update
;; pattern from log-browser: fixed telemetry columns, numeric refresh values, visible
;; and arena-only updates, selected-row detail, and the same fixed row activation path.
(noir-app
 (font-asset #:manifest "assets/fontc/noir-desktop-sans-18/manifest.json"
             #:atlas "assets/fontc/noir-desktop-sans-18/atlas.r8")
 (visual-preset desktop-wide)
 (theme noir-monitor
   (color canvas "#0A1119" canvas-quiet "#0E1823"
          surface "#152231" surface-raised "#1D3042" surface-overlay "#274057"
          border-subtle "#27455B" border-strong "#3F7891"
          text-primary "#F0F7FB" text-muted "#9CB6C6" text-inverse "#071117"
          accent "#48C7A0" accent-muted "#1D4D47"
          success "#48C7A0" warning "#D9A84C" danger "#ED7083" info "#6FB5FF"
          panel "#1D3042" header "#1D3042" text "#F0F7FB" muted "#9CB6C6")
   (space xs 4 sm 8 md 12 lg 16 xl 24 page 32)
   (type caption 13 body 15 label 16 title 28 display 36)
   (radius control 6 card 10 panel 14 overlay 18)
   (elevation flat 0 border 1 raised 2 overlay 3))
 (state [monitor-detail-damage 0])
 (action open-monitor-detail (set monitor-detail-damage (+ monitor-detail-damage 1)))
 (list-navigation #:id monitor-navigation #:for telemetry-grid #:scrollbar monitor-scrollbar)
 ;; This application-level plan reuses the existing detail/color/append protocol.
 ;; The record itself is a telemetry schema: STATE HOST CPU MEM NET LAT JIT.
 (log-browser #:id telemetry-dashboard #:for telemetry-grid #:detail monitor-detail
   #:append ((9997 "WARN TAILA 090 700 080 020 010")
             (9998 "ERROR TAILB 097 882 091 024 021")
             (9999 "DEBUG TAILC 011 101 004 003 001")))
 (app-shell #:id monitor-shell
   (toolbar #:id monitor-app-bar #:text-id monitor-title #:label "REALTIME MONITOR TABLE" #:font-face noir-desktop-sans-18)
   (table-header #:id monitor-column-header #:text-id monitor-columns #:label "STATE HOST CPU MEM NET LAT JIT" #:font-face noir-desktop-sans-18)
   (surface #:id monitor-list-shell #:height 84 #:background (theme-color surface) #:elevation (theme-elevation border) #:clip true
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
   (detail-panel #:id monitor-detail-panel #:text-id monitor-detail #:dynamic monitor-detail-damage #:max-chars 29
                 #:background (theme-color surface-raised))
   (status-pill #:id monitor-refresh-bar #:button-id refresh-telemetry #:label-id refresh-telemetry-label
                #:button-label "REFRESH BATCH" #:label "REFRESH FIXED BATCH"
                #:font-face noir-desktop-sans-18 #:on open-monitor-detail #:background (theme-color accent-muted))))
