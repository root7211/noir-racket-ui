#lang noir/ui

;; Fixed-capacity uppercase command input. The command table itself is a macro-time
;; literal-to-slot lowering; command-buffer stores only the packed ASCII audit value.
(noir-app
  (state (command-buffer 0)
         (command-applied 0))
  (action gpu-command (set command-applied (+ command-applied 1)))
  (command-table #:field command-entry
    (command "GPU" #:action gpu-command))

  (column #:id command-palette #:padding 12 #:gap 6 #:background dark
    (text #:id command-title "NOIR COMMAND PALETTE")
    (text-field #:id command-entry
                #:state command-buffer
                #:max-chars 6
                #:tab-index 0
                #:charset ascii-upper
                #:placeholder "COMMAND"
                #:on-enter commit
                #:on-escape reset
                #:width 360)
    (progress #:id command-applied-bar #:dynamic command-applied #:max 4 #:width 360)
    (text #:id command-caption "GPU ENTER EXECUTES FIXED ACTION")))
