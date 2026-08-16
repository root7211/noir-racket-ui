#lang noir/ui

;; Log browser v1 is an application-layer consumer of the frozen long-list ABI.
;; Each register is a 32-cell fixed-width row with four compiler-fixed columns:
;; LEVEL | TIME | SOURCE | MESSAGE. Only four physical rows reach the GPU arena.
(noir-app
 (font-asset #:manifest "assets/fontc/noir-desktop-sans-18/manifest.json"
             #:atlas "assets/fontc/noir-desktop-sans-18/atlas.r8")
 (dynamic-font-cell-asset #:manifest "assets/fontc/noir-table-body-mono-16/manifest.json"
                          #:atlas "assets/fontc/noir-table-body-mono-16/atlas.r8")
 (visual-preset desktop-wide)
 (theme noir-desktop
   (color canvas "#0B0F16" canvas-quiet "#101620"
          surface "#171E2A" surface-raised "#202A3A" surface-overlay "#273449"
          border-subtle "#2B3850" border-strong "#42688D"
          text-primary "#F2F6FC" text-muted "#9CABBD" text-inverse "#08101A"
          accent "#5CA8FF" accent-muted "#244765"
          success "#4FCB9B" warning "#D8A34A" danger "#EE6B7B" info "#78A8FF"
          panel "#202A3A" header "#202A3A" text "#F2F6FC" muted "#9CABBD")
   (space xs 4 sm 8 md 12 lg 16 xl 24 page 32)
   (type caption 13 body 15 label 16 title 28 display 36)
   (radius control 6 card 10 panel 14 overlay 18)
   (elevation flat 0 border 1 raised 2 overlay 3))
 (state [detail-damage 0])
 ;; This action preserves the existing row-activation path. The transparent anchor below
 ;; creates a compiler-known local detail tile without changing selected detail glyphs.
 (action open-log-detail (set detail-damage (+ detail-damage 1)))
 (list-navigation #:id log-navigation #:for system-log #:scrollbar log-scrollbar)
 (log-browser #:id system-log-browser #:for system-log #:detail log-detail
   #:append ((9997 "WARN  TIME  AUTH  TOKEN RETRY")
             (9998 "ERROR TIME  AUTH  TOKEN DENIED")
             (9999 "DEBUG TIME  CACHE ROTATE DONE")))
 (app-shell #:id log-browser-dashboard
   ;; toolbar/table-header expand to the same stack + static page-2 text primitives.
   (toolbar #:id log-app-bar #:text-id log-title #:label "SYSTEM LOG BROWSER" #:font-face noir-desktop-sans-18)
   (table-header #:id log-column-header #:text-id log-columns #:label "LEVEL TIME SOURCE MESSAGE" #:font-face noir-desktop-sans-18)
   ;; surface expands to the original fixed list stack; the list ABI remains untouched.
   (surface #:id log-list-shell #:height 84 #:background (theme-color surface) #:elevation (theme-elevation border) #:clip true
     (virtual-list #:id system-log
                   #:logical-capacity 10000
                   #:physical-slots 4
                   #:visible-rows 3
                   #:row-height 28
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
                #:x 554 #:y 0 #:width 12 #:height 84 #:thumb-height 18))
   ;; detail-panel preserves the same dynamic glyph range and local action tile.
   (detail-panel #:id log-detail-panel #:text-id log-detail #:dynamic detail-damage #:max-chars 29
                 #:background (theme-color surface-raised))
   ;; status-pill expands to the original interactive button plus static page-2 label.
   (status-pill #:id log-append-bar #:button-id append-tail #:label-id append-tail-label
                #:button-label "APPEND TAIL" #:label "APPEND FIXED TAIL"
                #:font-face noir-desktop-sans-18 #:on open-log-detail #:background (theme-color accent-muted))))
