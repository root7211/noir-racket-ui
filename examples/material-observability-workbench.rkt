#lang noir/ui

;; Material Observability Workbench v1.
;; All three view subtrees are compiled as resident static resources. The rail changes
;; only compiler-proved alpha endpoints; the Systems viewport is the single 10,000-row
;; mutable arena and the deployment overlay remains a fixed modal subgraph.
(noir-app
 (font-asset #:manifest "assets/fontc/noir-desktop-sans-18/manifest.json"
             #:atlas "assets/fontc/noir-desktop-sans-18/atlas.r8")
 (dynamic-font-cell-asset #:manifest "assets/fontc/noir-table-body-mono-16/manifest.json"
                          #:atlas "assets/fontc/noir-table-body-mono-16/atlas.r8")
 (visual-preset desktop-wide)
 (material-profile material-dark)
 (state [workbench-view 0]
        [workbench-overlay-visible 0]
        [workbench-detail-damage 0])
 (action workbench-select-overview (set workbench-view 0))
 (action workbench-select-systems (set workbench-view 1))
 (action workbench-select-alerts (set workbench-view 2))
 (action workbench-open-detail (set workbench-detail-damage (+ workbench-detail-damage 1)))
 (action workbench-open-deployment (set workbench-overlay-visible 1))
 (action workbench-confirm-deployment (set workbench-overlay-visible 0))
 (action workbench-dismiss-deployment (set workbench-overlay-visible 0))
 (action workbench-pin-build (set workbench-overlay-visible 0))
 (action workbench-copy-artifact (set workbench-overlay-visible 0))
 (action workbench-export-manifest (set workbench-overlay-visible 0))
 (list-navigation #:id observability-list-navigation #:for observability-log #:scrollbar observability-scrollbar)
 (log-browser #:id observability-log-browser #:for observability-log #:detail observability-detail
   #:append ((9997 "WARN  TIME  AUTH  TOKEN RETRY")
             (9998 "ERROR TIME  AUTH  TOKEN DENIED")
             (9999 "DEBUG TIME  CACHE ROTATE DONE")))
 (material-observability-workbench
  #:id observability-workbench
  #:rail observability-rail
  #:systems-list observability-log
  #:views ((observability-overview overview-view)
           (observability-systems systems-view)
           (observability-alerts alerts-view)))

 (stack #:id material-observability-workbench #:width 1216 #:height 656 #:clip #t
        #:background (theme-color background)
   (material-nav-rail #:id observability-rail #:state workbench-view #:active observability-overview
                      #:font-face noir-desktop-sans-18 #:x 0 #:y 0 #:width 180 #:height 656
     (material-destination #:id observability-overview #:label-id observability-overview-label #:label "Overview" #:icon dashboard #:on workbench-select-overview)
     (material-destination #:id observability-systems #:label-id observability-systems-label #:label "Systems" #:icon status #:on workbench-select-systems)
     (material-destination #:id observability-alerts #:label-id observability-alerts-label #:label "Alerts" #:icon more #:on workbench-select-alerts))

   (material-app-bar #:id observability-app-bar #:title-id observability-app-bar-title
                     #:title "Material observability workbench" #:font-face noir-desktop-sans-18
                     #:x 204 #:y 0 #:width 996)
   (material-filled-button #:id observability-deploy-action #:button-id observability-deploy-button
                           #:label-id observability-deploy-label #:label "Deploy plan"
                           #:font-face noir-desktop-sans-18 #:on workbench-open-deployment
                           #:x 1000 #:y 12 #:width 176 #:height 40)

   ;; View 0 — static topology and compiler proof summary.
   (stack #:id overview-view #:x 204 #:y 72 #:width 996 #:height 560 #:visual-anchor #t
          #:background (theme-color background)
     (material-card #:id overview-health-card #:x 0 #:y 16 #:width 482 #:height 220
                    #:background (theme-color surface-container-low)
       (text #:id overview-health-title #:x 24 #:y 22 #:width 410 #:height 28
             #:font-face noir-desktop-sans-18 #:font-scale 0.82 #:text-inset 0.0 "Service health")
       (overlay #:id overview-health-accent #:x 24 #:y 170 #:width 434 #:height 4
                #:background (theme-color primary) #:opacity 1.0 #:z 8))
     (material-card #:id overview-render-card #:x 514 #:y 16 #:width 482 #:height 220
                    #:background (theme-color surface-container)
       (text #:id overview-render-title #:x 24 #:y 22 #:width 410 #:height 28
             #:font-face noir-desktop-sans-18 #:font-scale 0.82 #:text-inset 0.0 "Render budget")
       (overlay #:id overview-render-accent #:x 24 #:y 170 #:width 434 #:height 4
                #:background (theme-color tertiary) #:opacity 1.0 #:z 8))
     (material-card #:id overview-proof-card #:x 0 #:y 268 #:width 996 #:height 252
                    #:background (theme-color surface-container-high)
       (text #:id overview-proof-body-a #:x 24 #:y 72 #:width 850 #:height 28
             #:font-face noir-desktop-sans-18 #:font-scale 0.72 #:text-inset 0.0 "Compiler-proved state: rail selection, data viewport, overlay, and focus ring share one fixed scene.")))

   ;; View 1 — the sole mutable 10,000-row Systems arena.
   (stack #:id systems-view #:x 204 #:y 72 #:width 996 #:height 560 #:visual-anchor #t
          #:background (theme-color background)
     (surface #:id systems-table-card #:x 0 #:y 16 #:width 996 #:height 368
              #:background (theme-color surface-container-low) #:elevation (theme-elevation raised)
              #:radius (theme-radius card) #:clip #t
       (text #:id systems-table-title #:x 24 #:y 16 #:width 420 #:height 30
             #:font-face noir-desktop-sans-18 #:font-scale 0.82 #:text-inset 0.0 "System event stream")
       (stack #:id systems-column-header #:x 20 #:y 62 #:width 956 #:height 34 #:visual-anchor #t
              #:background (theme-color surface-container-high)
         (text #:id systems-column-labels #:x 14 #:y 0 #:width 916 #:height 32
               #:font-face noir-desktop-sans-18 #:font-scale 0.70 #:text-inset 0.0 "Level   Time   Source   Message"))
       (surface #:id systems-list-shell #:x 20 #:y 98 #:width 956 #:height 144
                #:background (theme-color surface-container-low) #:elevation (theme-elevation level-0) #:clip #t
         (virtual-list #:id observability-log
                       #:logical-capacity 10000
                       #:physical-slots 4
                       #:visible-rows 4
                       #:row-height 32
                       #:max-chars 32
           (data-register-table #:id observability-log-data #:font-face noir-table-body-mono-16 #:seed "INFO  TIME  CORE  STARTUP"
             (data-update-batch #:id bootstrap-observability-log
               ((0 "INFO  TIME  CORE  STARTUP"))))
           (on-activate workbench-open-detail)
           (row-template ((observability-row-a "INFO  TIME  CORE  STARTUP")
                          (observability-row-b "INFO  TIME  CORE  STARTUP")
                          (observability-row-c "INFO  TIME  CORE  STARTUP")
                          (observability-row-d "INFO  TIME  CORE  STARTUP"))))
         (scrollbar #:id observability-scrollbar #:for observability-log
                    #:x 940 #:y 0 #:width 12 #:height 144 #:thumb-height 24))
)
     (material-card #:id systems-detail-card #:x 0 #:y 408 #:width 996 #:height 128
                    #:background (theme-color surface-container)
       (detail-panel #:id systems-detail-panel #:text-id observability-detail #:dynamic workbench-detail-damage #:max-chars 29
                     #:x 24 #:y 46 #:width 548 #:height 50 #:background (theme-color surface-container))
       (material-filled-button #:id systems-append-action #:button-id systems-append-button
                               #:label-id systems-append-label #:label "Append tail"
                               #:font-face noir-desktop-sans-18 #:on workbench-open-detail
                               #:x 772 #:y 64 #:width 176 #:height 40)))

   ;; View 2 — fixed alert summary; no second data arena is permitted in v1.
   (stack #:id alerts-view #:x 204 #:y 72 #:width 996 #:height 560 #:visual-anchor #t
          #:background (theme-color background)
     (material-card #:id alerts-summary-card #:x 0 #:y 16 #:width 996 #:height 168
                    #:background (theme-color surface-container-high)
       (text #:id alerts-summary-title #:x 24 #:y 22 #:width 620 #:height 30
             #:font-face noir-desktop-sans-18 #:font-scale 0.82 #:text-inset 0.0 "Alert posture")
       (overlay #:id alerts-summary-accent #:x 24 #:y 122 #:width 948 #:height 4
                #:background (theme-color error) #:opacity 1.0 #:z 8))
     (material-card #:id alerts-proof-card #:x 0 #:y 216 #:width 482 #:height 276
                    #:background (theme-color surface-container-low)
       (text #:id alerts-proof-title #:x 24 #:y 22 #:width 410 #:height 28
             #:font-face noir-desktop-sans-18 #:font-scale 0.80 #:text-inset 0.0 "Visible endpoint"))

     (material-card #:id alerts-action-card #:x 514 #:y 216 #:width 482 #:height 276
                    #:background (theme-color surface-container)
       (text #:id alerts-action-title #:x 24 #:y 22 #:width 410 #:height 28
             #:font-face noir-desktop-sans-18 #:font-scale 0.80 #:text-inset 0.0 "Deployment guard")
))

   (material-overlay-state #:id observability-deployment-overlay #:state workbench-overlay-visible #:initial 0
                           #:open-on workbench-open-deployment
                           #:close-on (workbench-confirm-deployment workbench-dismiss-deployment workbench-pin-build workbench-copy-artifact workbench-export-manifest)
                           #:modal-focus (observability-confirm observability-dismiss observability-menu-pin observability-menu-copy observability-menu-export)
     (material-dialog #:id observability-deployment-dialog #:scrim-id observability-deployment-scrim
                      #:title-id observability-dialog-title #:body-id observability-dialog-body
                      #:confirm-id observability-confirm #:dismiss-id observability-dismiss
                      #:title "Deploy observability plan" #:body "The workbench keeps every view and focus endpoint resident."
                      #:confirm-label "Deploy" #:dismiss-label "Cancel"
                      #:font-face noir-desktop-sans-18 #:confirm-on workbench-confirm-deployment #:dismiss-on workbench-dismiss-deployment
                      #:scrim-on workbench-dismiss-deployment
                      #:x 360 #:y 184 #:width 496 #:height 236)
     (material-menu #:id observability-deployment-menu #:font-face noir-desktop-sans-18
                    #:x 896 #:y 132 #:width 224 #:height 148
       (material-menu-item #:id observability-menu-pin #:label-id observability-menu-pin-label #:label "Pin build" #:icon pin #:on workbench-pin-build)
       (material-menu-item #:id observability-menu-copy #:label-id observability-menu-copy-label #:label "Copy artifact" #:icon copy #:on workbench-copy-artifact)
       (material-menu-item #:id observability-menu-export #:label-id observability-menu-export-label #:label "Export manifest" #:icon export #:on workbench-export-manifest)))))
