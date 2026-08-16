#lang noir/ui

;; Visual Language v2 monitor. Static chrome is page 2; the 10,000-record
;; telemetry table remains a fixed page-3 cell arena with compiler-proved refresh.
(noir-app
 (font-asset #:manifest "assets/fontc/noir-desktop-sans-18/manifest.json"
             #:atlas "assets/fontc/noir-desktop-sans-18/atlas.r8")
 (dynamic-font-cell-asset #:manifest "assets/fontc/noir-table-body-mono-16/manifest.json"
                          #:atlas "assets/fontc/noir-table-body-mono-16/atlas.r8")
 (visual-preset desktop-wide)
 (theme noir-ink-v2
   (color canvas "#020306" canvas-quiet "#03050A" rail "#05070B"
          surface "#080B11" surface-raised "#0D111A" surface-hover "#121824"
          surface-active "#192235" surface-overlay "#101622"
          border-subtle "#151C29" border-strong "#26344A"
          text-primary "#C8D5E8" text-secondary "#8FA1BA" text-muted "#586A83" text-inverse "#03050A"
          accent "#174F9E" accent-muted "#0B2145"
          success "#087055" warning "#8A5A0A" danger "#8C1730" info "#145E9A"
          panel "#0D111A" header "#0D111A" text "#C8D5E8" muted "#586A83")
   (space hairline 1 xxs 2 xs 4 sm 6 md 8 control 10 card 12 lg 16 xl 20 xxl 24 page 32 section 40)
   (type meta 11 caption 12 body 14 label 15 control 16 section 20 title 24 display 32)
   (radius compact 4 control 6 field 8 card 12 panel 16 overlay 18)
   (elevation flat 0 border 1 raised 2 overlay 3))
 (state [monitor-detail-damage 0])
 (action open-monitor-detail (set monitor-detail-damage (+ monitor-detail-damage 1)))
 (list-navigation #:id monitor-navigation #:for telemetry-grid #:scrollbar monitor-scrollbar)
 (log-browser #:id telemetry-dashboard #:for telemetry-grid #:detail monitor-detail
   #:append ((9997 "WARN TAILA 090 700 080 020 010")
             (9998 "ERROR TAILB 097 882 091 024 021")
             (9999 "DEBUG TAILC 011 101 004 003 001")))

 (workspace-shell #:id monitor-shell
                  #:rail-id monitor-brand-rail #:brand-id monitor-brand #:meta-id monitor-brand-meta
                  #:brand "NOIR" #:meta "LIVE SYSTEMS" #:font-face noir-desktop-sans-18
   (page-header #:id monitor-app-bar #:eyebrow-id monitor-eyebrow #:title-id monitor-title #:meta-id monitor-header-meta
                #:eyebrow "INFRASTRUCTURE" #:title "REALTIME MONITOR" #:meta "FIXED BATCH  PROOF LOCKED"
                #:font-face noir-desktop-sans-18 #:x 204 #:y 16 #:width 996)

   (metric-tile #:id monitor-capacity-tile #:label-id monitor-capacity-label #:value-id monitor-capacity-value
                #:label "LOGICAL NODES" #:value "10000 HOSTS" #:font-face noir-desktop-sans-18
                #:x 204 #:y 108 #:width 240 #:accent (theme-color accent))
   (metric-tile #:id monitor-visible-tile #:label-id monitor-visible-label #:value-id monitor-visible-value
                #:label "VISIBLE ARENA" #:value "4 ROW SLOTS" #:font-face noir-desktop-sans-18
                #:x 456 #:y 108 #:width 240 #:accent (theme-color info))
   (metric-tile #:id monitor-update-tile #:label-id monitor-update-label #:value-id monitor-update-value
                #:label "UPDATE ROUTE" #:value "ZERO COPY" #:font-face noir-desktop-sans-18
                #:x 708 #:y 108 #:width 240 #:accent (theme-color success))
   (metric-tile #:id monitor-state-tile #:label-id monitor-state-label #:value-id monitor-state-value
                #:label "SYSTEM STATE" #:value "NOMINAL" #:font-face noir-desktop-sans-18
                #:x 960 #:y 108 #:width 240 #:accent (theme-color success))

   (surface #:id monitor-table-card #:x 204 #:y 196 #:width 996 #:height 300
            #:background (theme-color surface) #:elevation (theme-elevation raised)
            #:radius (theme-radius card) #:clip true
     (text #:id monitor-table-title #:x 20 #:y 8 #:width 420 #:height 36
           #:font-face noir-desktop-sans-18 #:font-scale 0.82 #:text-inset 0.0 "TELEMETRY GRID")
     (text #:id monitor-table-meta #:x 724 #:y 12 #:width 248 #:height 24
           #:font-face noir-desktop-sans-18 #:font-scale 0.72 #:text-inset 0.0 "36 CELLS  FIXED ADDRESS")
     (stack #:id monitor-column-header #:x 0 #:y 48 #:width 996 #:height 36 #:visual-anchor #t
            #:background (theme-color surface-raised)
       (text #:id monitor-columns #:x 16 #:width 940 #:height 36
             #:font-face noir-desktop-sans-18 #:font-scale 0.72 #:text-inset 0.0
             "STATE  HOST  CPU  MEM  NET  LAT  JIT"))
     (surface #:id monitor-list-shell #:x 0 #:y 84 #:width 996 #:height 128
              #:background (theme-color surface) #:elevation (theme-elevation flat) #:clip true
       (virtual-list #:id telemetry-grid
                     #:logical-capacity 10000
                     #:physical-slots 4
                     #:visible-rows 4
                     #:row-height 32
                     #:max-chars 36
         (data-register-table #:id telemetry-registers #:font-face noir-table-body-mono-16 #:seed "NOMINAL ALPHA LOW MID LOW FAST LOW"
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
                  #:x 980 #:y 0 #:width 12 #:height 128 #:thumb-height 24))
     (text #:id monitor-table-footnote #:x 20 #:y 238 #:width 620 #:height 26
           #:font-face noir-desktop-sans-18 #:font-scale 0.72 #:text-inset 0.0
           "VISIBLE REFRESH WRITES  OFFSCREEN REFRESH STAYS ARENA ONLY"))

   (surface #:id monitor-detail-card #:x 204 #:y 512 #:width 996 #:height 128
            #:background (theme-color surface-raised) #:elevation (theme-elevation raised)
            #:radius (theme-radius card) #:clip true
     (text #:id monitor-detail-title #:x 20 #:y 10 #:width 420 #:height 28
           #:font-face noir-desktop-sans-18 #:font-scale 0.78 #:text-inset 0.0 "SELECTED HOST")
     (detail-panel #:id monitor-detail-panel #:text-id monitor-detail #:dynamic monitor-detail-damage #:max-chars 29
                   #:x 20 #:y 42 #:width 520 #:height 54 #:background (theme-color surface-raised))
     (action-button #:id monitor-refresh-action #:button-id refresh-telemetry #:label-id refresh-telemetry-label
                    #:label "REFRESH" #:font-face noir-desktop-sans-18 #:on open-monitor-detail
                    #:x 788 #:y 72 #:width 176 #:height 40 #:variant filled))))
