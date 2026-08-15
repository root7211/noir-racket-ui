#lang noir/ui

;; Macro form of desktop-components-primitive.rkt. The exported Scene must be identical
;; after provenance attestation fields are removed.
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
 (app-shell #:id component-fixture-shell
   (toolbar #:id component-fixture-toolbar #:text-id component-fixture-title
            #:label "COMPILED DESKTOP CHROME" #:font-face noir-desktop-sans-18)
   (table-header #:id component-fixture-header #:text-id component-fixture-columns
                 #:label "STATE VALUE LATENCY" #:font-face noir-desktop-sans-18)
   (surface #:id component-fixture-surface #:height 22 #:background (theme-color panel) #:clip false
     (text #:id component-fixture-surface-text "FIXED SURFACE"))
   (detail-panel #:id component-fixture-detail #:text-id component-fixture-detail-text
                 #:dynamic detail-damage #:max-chars 8)
   (status-pill #:id component-fixture-status #:button-id component-fixture-status-button
                #:label-id component-fixture-status-label #:button-label "REFRESH"
                #:label "REFRESH DETAIL" #:font-face noir-desktop-sans-18
                #:on refresh-detail #:background (theme-color accent))))
