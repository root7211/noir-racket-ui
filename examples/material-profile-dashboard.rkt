#lang noir/ui

;; Material Profile v1 fixture: every token, component geometry, glyph run and
;; action write is fixed at expansion time. The profile is deliberately dark and
;; static; it does not expose runtime dynamic color, ripple, icon lookup or reflow.
(noir-app
 (font-asset #:manifest "assets/fontc/noir-desktop-sans-18/manifest.json"
             #:atlas "assets/fontc/noir-desktop-sans-18/atlas.r8")
 (visual-preset desktop-wide)
 (material-profile material-dark)
 (state [refresh-count 0]
        [material-navigation 0])
 (action material-refresh (set refresh-count (+ refresh-count 1)))
 (action material-select-overview (set material-navigation 0))
 (action material-select-systems (set material-navigation 1))
 (action material-select-alerts (set material-navigation 2))

 (stack #:id material-profile-dashboard #:width 1216 #:height 656 #:clip #t
        #:background (theme-color background)
   (material-nav-rail #:id material-nav-rail #:state material-navigation #:active material-overview
                      #:font-face noir-desktop-sans-18 #:x 0 #:y 0 #:width 180 #:height 656
     (material-destination #:id material-overview #:label-id material-overview-label #:label "Overview" #:icon dashboard #:on material-select-overview)
     (material-destination #:id material-systems #:label-id material-systems-label #:label "Systems" #:icon status #:on material-select-systems)
     (material-destination #:id material-alerts #:label-id material-alerts-label #:label "Alerts" #:icon more #:on material-select-alerts))

   (material-app-bar #:id material-app-bar #:title-id material-app-bar-title
                     #:title "System overview" #:font-face noir-desktop-sans-18
                     #:x 204 #:y 0 #:width 996)

   (material-card #:id material-summary-card #:x 204 #:y 88 #:width 482 #:height 238
                  #:background (theme-color surface-container-low)
     (text #:id material-summary-title #:x 24 #:y 20 #:width 434 #:height 32
           #:font-face noir-desktop-sans-18 #:font-scale 0.80 #:text-inset 0.0 "Service health")
     (text #:id material-summary-body #:x 24 #:y 64 #:width 434 #:height 30
           #:font-face noir-desktop-sans-18 #:font-scale 0.72 #:text-inset 0.0 "Compiled telemetry surface")
     (text #:id material-summary-state #:x 24 #:y 112 #:width 434 #:height 32
           #:font-face noir-desktop-sans-18 #:font-scale 0.78 #:text-inset 0.0 "All systems nominal")
     (overlay #:id material-summary-accent #:x 24 #:y 170 #:width 434 #:height 4
              #:background (theme-color primary) #:opacity 1.0 #:z 8))

   (material-card #:id material-performance-card #:x 718 #:y 88 #:width 482 #:height 238
                  #:background (theme-color surface-container)
     (text #:id material-performance-title #:x 24 #:y 20 #:width 434 #:height 32
           #:font-face noir-desktop-sans-18 #:font-scale 0.80 #:text-inset 0.0 "Render budget")
     (text #:id material-performance-body #:x 24 #:y 64 #:width 434 #:height 30
           #:font-face noir-desktop-sans-18 #:font-scale 0.72 #:text-inset 0.0 "Frozen GPU write ranges")
     (text #:id material-performance-state #:x 24 #:y 112 #:width 434 #:height 32
           #:font-face noir-desktop-sans-18 #:font-scale 0.78 #:text-inset 0.0 "Proof path ready")
     (overlay #:id material-performance-accent #:x 24 #:y 170 #:width 434 #:height 4
              #:background (theme-color tertiary) #:opacity 1.0 #:z 8))

   (material-card #:id material-activity-card #:x 204 #:y 358 #:width 996 #:height 254
                  #:background (theme-color surface-container-high)
     (text #:id material-activity-title #:x 24 #:y 20 #:width 720 #:height 32
           #:font-face noir-desktop-sans-18 #:font-scale 0.80 #:text-inset 0.0 "Recent compiler activity")
     (text #:id material-activity-body #:x 24 #:y 68 #:width 720 #:height 28
           #:font-face noir-desktop-sans-18 #:font-scale 0.72 #:text-inset 0.0 "Static plan updated without reflow")
     (text #:id material-refresh-label #:x 24 #:y 132 #:width 240 #:height 26
           #:font-face noir-desktop-sans-18 #:font-scale 0.72 #:text-inset 0.0 "Refreshes")
     (text #:id material-refresh-count #:x 24 #:y 164 #:width 90 #:height 34
           #:dynamic refresh-count #:max-chars 3)
     (material-filled-button #:id material-refresh-action #:button-id material-refresh-button
                             #:label-id material-refresh-button-label #:label "Refresh"
                             #:font-face noir-desktop-sans-18 #:on material-refresh
                             #:x 772 #:y 168 #:width 176 #:height 48))))
