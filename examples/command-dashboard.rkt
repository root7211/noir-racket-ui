#lang noir/ui

(noir-app
  (state
    (command-value 0)
    (query-value 0)
    (submitted 2))

  (action apply-command (set submitted (+ submitted 1)))
  ;; 固定 field actions 将两个 text rect 纳入既有 render/tile schedule，供 Focus/Keyboard Command Map 复用。
  (action refresh-command (set command-value (+ command-value 1)))
  (action refresh-query (set query-value (+ query-value 1)))

  (column #:id command-form #:padding 24 #:gap 12 #:background dark
    (text #:id command-title #:width 572 #:height 28 "COMMAND FORM")
    (text-field #:id command-field
                #:state command-value
                #:max-chars 3
                #:tab-index 0
                #:charset digits
                #:placeholder "VALUE"
                #:on-enter apply-command
                #:on-escape reset
                #:width 240)
    (text-field #:id query-field
                #:state query-value
                #:max-chars 3
                #:tab-index 10
                #:charset digits
                #:placeholder "QUERY"
                #:on-escape reset
                #:width 240)
    (progress #:id apply-progress #:dynamic submitted #:max 10 #:width 360 #:height 18)))
