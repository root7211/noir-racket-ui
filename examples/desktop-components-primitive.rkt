#lang noir/ui

;; Hand-written primitive baseline for desktop component macro v1/v2 equivalence.
;; Every node below mirrors the current macro expansion exactly; the oracle removes
;; provenance fingerprints only and compares the entire remaining runtime Scene.
(noir-app
 (font-asset #:manifest "assets/fontc/noir-desktop-sans-18/manifest.json"
             #:atlas "assets/fontc/noir-desktop-sans-18/atlas.r8")
 (theme fixture-theme
   (color canvas "#0E1117" surface "#171B24" surface-raised "#202E46"
          panel "#1F2633" header "#202E46" border-subtle "#2B313E" border-strong "#465268"
          accent "#4C8DFF" danger "#F06A6A" text "#F4F7FB" muted "#9AA6B7")
   (space xs 4 sm 8 md 12 lg 16 xl 24 page 32)
   (type caption 13 body 15 label 16 title 28 display 36)
   (radius control 6 card 10 panel 14 overlay 18))
 (state [detail-damage 0])
 (action refresh-detail (set detail-damage (+ detail-damage 1)))
 (stack #:id component-fixture-shell #:height 328 #:clip #t
        #:background (theme-color canvas)
   (column #:id component-fixture-shell$content #:visual-flow #t
           #:gap (theme-space sm) #:padding (theme-space lg)
     (stack #:id component-fixture-toolbar #:height 34 #:background (theme-color surface-raised)
       (text #:id component-fixture-title #:height 34 #:background (theme-color surface-raised)
             #:font-face noir-desktop-sans-18 "COMPILED DESKTOP CHROME")
       (overlay #:id component-fixture-toolbar$divider #:y 33 #:height 1
                #:background (theme-color border-strong) #:opacity 1.0 #:z 10))
     (stack #:id component-fixture-header #:height 24 #:background (theme-color surface)
       (text #:id component-fixture-columns #:height 24 #:background (theme-color surface)
             #:font-face noir-desktop-sans-18 "STATE VALUE LATENCY")
       (overlay #:id component-fixture-header$divider #:y 23 #:height 1
                #:background (theme-color border-subtle) #:opacity 1.0 #:z 10))
     (stack #:id component-fixture-surface #:height 22 #:visual-anchor #t
            #:clip #f #:background (theme-color panel)
       (text #:id component-fixture-surface-text "FIXED SURFACE"))
     (stack #:id component-fixture-detail #:x 0 #:y 0 #:height 34 #:visual-anchor #t
            #:background (theme-color surface-raised)
       (text #:id component-fixture-detail-text #:height 34 #:background (theme-color surface-raised)
             #:dynamic detail-damage #:max-chars 8 #:charset ascii-upper)
       (overlay #:id component-fixture-detail$divider #:height 1
                #:background (theme-color border-subtle) #:opacity 1.0 #:z 10))
     (stack #:id component-fixture-status #:height 30 #:background (theme-color accent)
       (button #:id component-fixture-status-button #:height 30 #:background (theme-color accent)
               "REFRESH" #:on refresh-detail)
       (text #:id component-fixture-status-label #:height 30 #:background (theme-color accent)
             #:font-face noir-desktop-sans-18 "REFRESH DETAIL")))))
