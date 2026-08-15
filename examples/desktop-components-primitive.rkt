#lang noir/ui

;; Hand-written primitive baseline for desktop component macro v1 equivalence.
(noir-app
 (font-asset #:manifest "assets/fontc/noir-desktop-sans-18/manifest.json"
             #:atlas "assets/fontc/noir-desktop-sans-18/atlas.r8")
 (theme fixture-theme
   (color canvas "#0E1117" surface "#171B24" panel "#1F2633" header "#202E46"
          accent "#4C8DFF" danger "#F06A6A" text "#F4F7FB" muted "#9AA6B7")
   (space xs 4 sm 8 md 12 lg 16 xl 24 page 32)
   (type caption 13 body 15 label 16 title 28 display 36)
   (radius control 6 card 10 panel 14 overlay 18))
 (state [detail-damage 0])
 (action refresh-detail (set detail-damage (+ detail-damage 1)))
 (column #:id component-fixture-shell #:gap (theme-space sm) #:padding (theme-space lg)
         #:background (theme-color canvas) #:radius (theme-radius panel)
   (stack #:id component-fixture-toolbar #:height 34 #:background (theme-color header)
     (text #:id component-fixture-title #:height 34 #:background (theme-color header)
           #:font-face noir-desktop-sans-18 "COMPILED DESKTOP CHROME"))
   (stack #:id component-fixture-header #:height 24 #:background (theme-color surface)
     (text #:id component-fixture-columns #:height 24 #:background (theme-color surface)
           #:font-face noir-desktop-sans-18 "STATE VALUE LATENCY"))
   (stack #:id component-fixture-surface #:height 22 #:clip false #:background (theme-color panel)
     (text #:id component-fixture-surface-text "FIXED SURFACE"))
   (stack #:id component-fixture-detail #:height 34 #:background (theme-color surface)
     (text #:id component-fixture-detail-text #:height 34 #:background (theme-color surface)
           #:dynamic detail-damage #:max-chars 8))
   (stack #:id component-fixture-status #:height 30 #:background (theme-color accent)
     (button #:id component-fixture-status-button #:height 30 #:background (theme-color accent)
             "REFRESH" #:on refresh-detail)
     (text #:id component-fixture-status-label #:height 30 #:background (theme-color accent)
           #:font-face noir-desktop-sans-18 "REFRESH DETAIL"))))
