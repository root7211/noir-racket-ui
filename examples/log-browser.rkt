#lang noir/ui

;; Log browser v1 is an application-layer consumer of the frozen long-list ABI.
;; Each register is a 32-cell fixed-width row with four compiler-fixed columns:
;; LEVEL | TIME | SOURCE | MESSAGE. Only four physical rows reach the GPU arena.
(noir-app
 (font-asset #:manifest "assets/fontc/noir-desktop-sans-18/manifest.json"
             #:atlas "assets/fontc/noir-desktop-sans-18/atlas.r8")
 (theme noir-desktop
   (color canvas "#0E1117" surface "#171B24" panel "#1F2633" header "#202E46"
          accent "#4C8DFF" danger "#F06A6A" text "#F4F7FB" muted "#9AA6B7")
   (space xs 4 sm 8 md 12 lg 16 xl 24 page 32)
   (type caption 13 body 15 label 16 title 28 display 36)
   (radius control 6 card 10 panel 14 overlay 18))
 (state [detail-damage 0])
 ;; This action preserves the existing row-activation path. The transparent anchor below
 ;; creates a compiler-known local detail tile without changing selected detail glyphs.
 (action open-log-detail (set detail-damage (+ detail-damage 1)))
 (list-navigation #:id log-navigation #:for system-log #:scrollbar log-scrollbar)
 (log-browser #:id system-log-browser #:for system-log #:detail log-detail
   #:append ((9997 "WARN  TIME  AUTH  TOKEN RETRY")
             (9998 "ERROR TIME  AUTH  TOKEN DENIED")
             (9999 "DEBUG TIME  CACHE ROTATE DONE")))
 (column #:id log-browser-dashboard #:gap (theme-space sm) #:padding (theme-space lg) #:background (theme-color canvas) #:radius (theme-radius panel)
   ;; Top application bar: the title remains on a dark, fixed high-contrast surface.
   (stack #:id log-app-bar #:height 34 #:background (theme-color header)
     (text #:id log-title #:height 34 #:background (theme-color header) #:font-face noir-desktop-sans-18 "SYSTEM LOG BROWSER"))
   ;; A distinct, compiler-fixed table header makes the row template legible as four fields.
   (stack #:id log-column-header #:height 24 #:background (theme-color surface)
     (text #:id log-columns #:height 24 #:background (theme-color surface) #:font-face noir-desktop-sans-18 "LEVEL TIME SOURCE MESSAGE"))
   ;; The list itself keeps its original 3-row / 4-slot compact arena and scrollbar ABI.
   (stack #:id log-list-shell #:height 84 #:clip true #:background (theme-color panel)
     (virtual-list #:id system-log
                   #:logical-capacity 10000
                   #:physical-slots 4
                   #:visible-rows 3
                   #:row-height 28
                   #:max-chars 32
       (data-register-table #:id system-log-data #:seed "INFO  TIME  CORE  STARTUP"
         (data-update-batch #:id bootstrap-system-log
           ((0 "INFO  TIME  CORE  STARTUP"))))
       (on-activate open-log-detail)
       (row-template ((log-row-a "INFO  TIME  CORE  STARTUP")
                      (log-row-b "INFO  TIME  CORE  STARTUP")
                      (log-row-c "INFO  TIME  CORE  STARTUP")
                      (log-row-d "INFO  TIME  CORE  STARTUP"))))
     (scrollbar #:id log-scrollbar #:for system-log
                #:x 554 #:y 0 #:width 12 #:height 84 #:thumb-height 18))
   ;; Dynamic placement makes this compiler-fixed glyph range part of the local action tile.
   ;; Selection and activation overwrite the same admitted cells with selected-row detail.
   (stack #:id log-detail-panel #:height 34 #:background (theme-color surface)
     (text #:id log-detail #:height 34 #:background (theme-color surface) #:dynamic detail-damage #:max-chars 29))
   ;; Button geometry remains the only interactive target. Its separate text overlay is a
   ;; compiler-fixed accessible label instead of relying on unrendered button labels.
   (stack #:id log-append-bar #:height 30 #:background (theme-color accent)
     (button #:id append-tail #:height 30 #:background (theme-color accent) "APPEND TAIL" #:on open-log-detail)
     (text #:id append-tail-label #:height 30 #:background (theme-color accent) #:font-face noir-desktop-sans-18 "APPEND FIXED TAIL"))))
