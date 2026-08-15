#lang noir/ui

;; `tab-index` 是唯一的编译期排序键，故 surface order 不参与运行时焦点决策。
;; query-field 在 tree 中先出现但 tab-index=20；command-field 后出现却 tab-index=5。
(noir-app
 (state
  [query-value 12]
  [command-value 34])

 ;; 这些 action 让两个固定 text field 的 glyph rect 进入 action/tile schedule。
 ;; 本阶段不实现字符键入；Tab/Shift+Tab 只消费 compiler Focus Graph。
 (action refresh-query
  (set query-value (+ query-value 1)))
 (action refresh-command
  (set command-value (+ command-value 1)))

 (column #:id focus-form #:gap 12 #:padding 24 #:background dark
   (text #:id focus-title "NOIR FOCUS FORM")
   (text-field #:id query-field #:state query-value #:max-chars 3 #:tab-index 20 #:width 240)
   (text-field #:id command-field #:state command-value #:max-chars 3 #:tab-index 5 #:width 240)))
