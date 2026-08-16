#lang noir/ui

;; Visual Language v2 application fixture. The workspace/card hierarchy is fully
;; expanded at compile time; the frozen 10,000-row list, page-3 cell register,
;; row activation and append action retain their existing semantic IDs.
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
 (state [detail-damage 0])
 (action open-log-detail (set detail-damage (+ detail-damage 1)))
 (list-navigation #:id log-navigation #:for system-log #:scrollbar log-scrollbar)
 (log-browser #:id system-log-browser #:for system-log #:detail log-detail
   #:append ((9997 "WARN  TIME  AUTH  TOKEN RETRY")
             (9998 "ERROR TIME  AUTH  TOKEN DENIED")
             (9999 "DEBUG TIME  CACHE ROTATE DONE")))

 (workspace-shell #:id log-browser-dashboard
                  #:rail-id log-brand-rail #:brand-id log-brand #:meta-id log-brand-meta
                  #:brand "NOIR" #:meta "COMPILED UI" #:font-face noir-desktop-sans-18
   (page-header #:id log-app-bar #:eyebrow-id log-eyebrow #:title-id log-title #:meta-id log-header-meta
                #:eyebrow "OBSERVABILITY" #:title "SYSTEM LOGS" #:meta "LIVE RING  STATIC PIPELINE"
                #:font-face noir-desktop-sans-18 #:x 204 #:y 16 #:width 996)

   (metric-tile #:id log-capacity-tile #:label-id log-capacity-label #:value-id log-capacity-value
                #:label "LOG CAPACITY" #:value "10000 EVENTS" #:font-face noir-desktop-sans-18
                #:x 204 #:y 108 #:width 240 #:accent (theme-color accent))
   (metric-tile #:id log-visible-tile #:label-id log-visible-label #:value-id log-visible-value
                #:label "VISIBLE ARENA" #:value "4 ROW SLOTS" #:font-face noir-desktop-sans-18
                #:x 456 #:y 108 #:width 240 #:accent (theme-color info))
   (metric-tile #:id log-font-tile #:label-id log-font-label #:value-id log-font-value
                #:label "TEXT PATH" #:value "PAGE 3 R8" #:font-face noir-desktop-sans-18
                #:x 708 #:y 108 #:width 240 #:accent (theme-color success))
   (metric-tile #:id log-proof-tile #:label-id log-proof-label #:value-id log-proof-value
                #:label "RUNTIME MODE" #:value "PROOF LOCKED" #:font-face noir-desktop-sans-18
                #:x 960 #:y 108 #:width 240 #:accent (theme-color warning))

   (surface #:id log-table-card #:x 204 #:y 196 #:width 996 #:height 300
            #:background (theme-color surface) #:elevation (theme-elevation raised)
            #:radius (theme-radius card) #:clip true
     (text #:id log-table-title #:x 20 #:y 8 #:width 420 #:height 36
           #:font-face noir-desktop-sans-18 #:font-scale 0.82 #:text-inset 0.0 "EVENT STREAM")
     (text #:id log-table-meta #:x 724 #:y 12 #:width 248 #:height 24
           #:font-face noir-desktop-sans-18 #:font-scale 0.72 #:text-inset 0.0 "4 VISIBLE  10000 TOTAL")
     (stack #:id log-column-header #:x 0 #:y 48 #:width 996 #:height 36 #:visual-anchor #t
            #:background (theme-color surface-raised)
       (text #:id log-columns #:x 16 #:width 940 #:height 36
             #:font-face noir-desktop-sans-18 #:font-scale 0.72 #:text-inset 0.0
             "LEVEL  TIME  SOURCE  MESSAGE"))
     (surface #:id log-list-shell #:x 0 #:y 84 #:width 996 #:height 128
              #:background (theme-color surface) #:elevation (theme-elevation flat) #:clip true
       (virtual-list #:id system-log
                     #:logical-capacity 10000
                     #:physical-slots 4
                     #:visible-rows 4
                     #:row-height 32
                     #:max-chars 32
         (data-register-table #:id system-log-data #:font-face noir-table-body-mono-16 #:seed "INFO  TIME  CORE  STARTUP"
           (data-update-batch #:id bootstrap-system-log
             ((0 "INFO  TIME  CORE  STARTUP"))))
         (on-activate open-log-detail)
         (row-template ((log-row-a "INFO  TIME  CORE  STARTUP")
                        (log-row-b "INFO  TIME  CORE  STARTUP")
                        (log-row-c "INFO  TIME  CORE  STARTUP")
                        (log-row-d "INFO  TIME  CORE  STARTUP"))))
       (scrollbar #:id log-scrollbar #:for system-log
                  #:x 980 #:y 0 #:width 12 #:height 128 #:thumb-height 24))
     (text #:id log-table-footnote #:x 20 #:y 238 #:width 620 #:height 26
           #:font-face noir-desktop-sans-18 #:font-scale 0.72 #:text-inset 0.0
           "END HOME PAGEUP PAGEDOWN  ENTER OPENS DETAIL"))

   (surface #:id log-detail-card #:x 204 #:y 512 #:width 996 #:height 128
            #:background (theme-color surface-raised) #:elevation (theme-elevation raised)
            #:radius (theme-radius card) #:clip true
     (text #:id log-detail-title #:x 20 #:y 10 #:width 420 #:height 28
           #:font-face noir-desktop-sans-18 #:font-scale 0.78 #:text-inset 0.0 "SELECTED EVENT")
     (detail-panel #:id log-detail-panel #:text-id log-detail #:dynamic detail-damage #:max-chars 29
                   #:x 20 #:y 42 #:width 520 #:height 54 #:background (theme-color surface-raised))
     (action-button #:id log-append-action #:button-id append-tail #:label-id append-tail-label
                    #:label "APPEND" #:font-face noir-desktop-sans-18 #:on open-log-detail
                    #:x 788 #:y 72 #:width 176 #:height 40 #:variant filled))))
