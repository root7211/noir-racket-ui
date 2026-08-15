#lang noir/ui

;; 所有 form-row/settings-form 在 macro expansion 中消失；Host 只会看到
;; column/row/text/text-field lowering 后的 stack/text/overlay/button 基础节点。
(noir-app
  (state
    [sample-interval 5]
    [alert-threshold 72]
    [batch-size 16])

  ;; 每个 action 只更新本行 state，因此 action text-run patch、field glyph range 与 tile
  ;; 归属在展开期一一对应。键入 glyph cell 本身仍不做 runtime layout 或 shaping。
  (action apply-sample-interval (set sample-interval (+ sample-interval 1)))
  (action apply-alert-threshold (set alert-threshold (+ alert-threshold 1)))
  (action apply-batch-size (set batch-size (+ batch-size 1)))

  ;; apply-all 的成员、提交顺序、State Slots 与 tile union 都在 macro expansion 期固定。
  (commit-group apply-all sample-interval alert-threshold batch-size)

  (column #:id settings-dashboard #:padding 4 #:gap 2 #:background dark
    (text #:id settings-title "NOIR SYSTEM SETTINGS")
    (settings-form #:id system-settings #:gap 2 #:padding 2 #:background dark
      (form-row #:id sample-interval-row
                #:label "SAMPLE INTERVAL"
                #:state sample-interval
                #:max-chars 3
                #:tab-index 0
                #:on-enter apply-all
                #:on-apply apply-sample-interval
                #:placeholder "SEC"
                #:apply-label "Apply")
      (form-row #:id alert-threshold-row
                #:label "ALERT THRESHOLD"
                #:state alert-threshold
                #:max-chars 3
                #:tab-index 1
                #:on-enter apply-all
                #:on-apply apply-alert-threshold
                #:placeholder "PCT"
                #:apply-label "Apply")
      (form-row #:id batch-size-row
                #:label "BATCH SIZE"
                #:state batch-size
                #:max-chars 3
                #:tab-index 2
                #:on-enter apply-all
                #:on-apply apply-batch-size
                #:placeholder "N"
                #:apply-label "Apply"))
    (row #:id settings-transaction-actions #:gap 8
      (transaction-button #:id apply-all-button #:transaction apply-all #:operation commit #:width 180 #:height 12 "Apply All")
      (transaction-button #:id reset-all-button #:transaction apply-all #:operation reset #:width 180 #:height 12 "Reset All"))))
