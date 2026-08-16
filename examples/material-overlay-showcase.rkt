#lang noir/ui

;; Material overlay showcase: dialog/menu composition is fully static. The three
;; actions only update one preallocated numeric glyph run; neither geometry nor
;; overlay visibility is decided at runtime in v1.
(noir-app
 (font-asset #:manifest "assets/fontc/noir-desktop-sans-18/manifest.json"
             #:atlas "assets/fontc/noir-desktop-sans-18/atlas.r8")
 (visual-preset desktop-wide)
 (material-profile material-dark)
 (state [overlay-count 0])
 (action overlay-confirm (set overlay-count (+ overlay-count 1)))
 (action overlay-dismiss (set overlay-count (+ overlay-count 1)))
 (action overlay-pin (set overlay-count (+ overlay-count 1)))
 (action overlay-copy (set overlay-count (+ overlay-count 1)))
 (action overlay-export (set overlay-count (+ overlay-count 1)))
 (stack #:id material-overlay-showcase #:width 1216 #:height 656 #:clip #t
        #:background (theme-color background)
   (material-app-bar #:id overlay-app-bar #:title-id overlay-app-bar-title
                     #:title "Deployment controls" #:font-face noir-desktop-sans-18
                     #:x 0 #:y 0 #:width 1216)
   (material-card #:id overlay-context-card #:x 248 #:y 112 #:width 560 #:height 248
                  (text #:id overlay-context-title #:x 24 #:y 24 #:width 400 #:height 28
                        #:font-face noir-desktop-sans-18 #:font-scale 0.82 #:text-inset 0.0
                        "Production deployment")
                  (text #:id overlay-context-body #:x 24 #:y 76 #:width 480 #:height 28
                        #:font-face noir-desktop-sans-18 #:font-scale 0.72 #:text-inset 0.0
                        "Compile a fixed release plan for the selected target."))
   (material-dialog #:id deployment-dialog #:scrim-id deployment-scrim
                    #:title-id deployment-dialog-title #:body-id deployment-dialog-body
                    #:confirm-id deployment-confirm #:dismiss-id deployment-dismiss
                    #:title "Deploy release plan" #:body "GPU work ranges and resources are already frozen."
                    #:confirm-label "Deploy" #:dismiss-label "Cancel"
                    #:font-face noir-desktop-sans-18 #:confirm-on overlay-confirm #:dismiss-on overlay-dismiss
                    #:x 360 #:y 184 #:width 496 #:height 236)
   (material-menu #:id deployment-menu #:font-face noir-desktop-sans-18
                  #:x 896 #:y 132 #:width 224 #:height 148
     (material-menu-item #:id menu-pin #:label-id menu-pin-label #:label "Pin build" #:icon pin #:on overlay-pin)
     (material-menu-item #:id menu-copy #:label-id menu-copy-label #:label "Copy artifact" #:icon copy #:on overlay-copy)
     (material-menu-item #:id menu-export #:label-id menu-export-label #:label "Export manifest" #:icon export #:on overlay-export))
   (text #:id overlay-count-label #:x 912 #:y 304 #:width 180 #:height 22
         #:font-face noir-desktop-sans-18 #:font-scale 0.72 #:text-inset 0.0 "Overlay actions")
   (text #:id overlay-count #:x 912 #:y 334 #:width 80 #:height 30
         #:dynamic overlay-count #:max-chars 2 #:charset digits)))
