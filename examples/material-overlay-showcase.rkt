#lang noir/ui

;; Material overlay showcase v2: every overlay surface is preallocated at compile
;; time. Runtime only selects a compiler-proved 0/1 visibility endpoint by writing
;; alpha lanes for fixed quad and glyph instances; it never creates or positions an
;; overlay.
(noir-app
 (font-asset #:manifest "assets/fontc/noir-desktop-sans-18/manifest.json"
             #:atlas "assets/fontc/noir-desktop-sans-18/atlas.r8")
 (visual-preset desktop-wide)
 (material-profile material-dark)
 (state [overlay-visible 0])
 (action overlay-open (set overlay-visible 1))
 (action overlay-confirm (set overlay-visible 0))
 (action overlay-dismiss (set overlay-visible 0))
 (action overlay-pin (set overlay-visible 0))
 (action overlay-copy (set overlay-visible 0))
 (action overlay-export (set overlay-visible 0))
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
                        "Open a fixed dialog and menu without runtime layout work.")
                  (material-filled-button #:id open-overlay-control #:button-id open-overlay-button
                                          #:label-id open-overlay-button-label #:label "Open controls"
                                          #:font-face noir-desktop-sans-18 #:on overlay-open
                                          #:x 24 #:y 156 #:width 176 #:height 48))
   (material-overlay-state #:id deployment-overlay #:state overlay-visible #:initial 0
                           #:open-on overlay-open
                           #:close-on (overlay-confirm overlay-dismiss overlay-pin overlay-copy overlay-export)
     (material-dialog #:id deployment-dialog #:scrim-id deployment-scrim
                      #:title-id deployment-dialog-title #:body-id deployment-dialog-body
                      #:confirm-id deployment-confirm #:dismiss-id deployment-dismiss
                      #:title "Deploy release plan" #:body "GPU work ranges and resources are already frozen."
                      #:confirm-label "Deploy" #:dismiss-label "Cancel"
                      #:font-face noir-desktop-sans-18 #:confirm-on overlay-confirm #:dismiss-on overlay-dismiss
                      #:scrim-on overlay-dismiss
                      #:x 360 #:y 184 #:width 496 #:height 236)
     (material-menu #:id deployment-menu #:font-face noir-desktop-sans-18
                    #:x 896 #:y 132 #:width 224 #:height 148
       (material-menu-item #:id menu-pin #:label-id menu-pin-label #:label "Pin build" #:icon pin #:on overlay-pin)
       (material-menu-item #:id menu-copy #:label-id menu-copy-label #:label "Copy artifact" #:icon copy #:on overlay-copy)
       (material-menu-item #:id menu-export #:label-id menu-export-label #:label "Export manifest" #:icon export #:on overlay-export)))))
