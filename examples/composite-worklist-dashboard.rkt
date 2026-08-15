#lang noir/ui

;; Static multi-field event fixture.  The layout deliberately follows the proven
;; Settings form shape; only the two literal multi-field event triggers differ.
(noir-app
  (state
    [sample-interval 5]
    [alert-threshold 72]
    [batch-size 16])

  (action apply-sample-interval (set sample-interval (+ sample-interval 1)))
  (action apply-alert-threshold (set alert-threshold (+ alert-threshold 1)))
  (action apply-batch-size (set batch-size (+ batch-size 1)))
  (commit-group apply-all sample-interval alert-threshold batch-size)

  (column #:id composite-worklist-dashboard #:padding 4 #:gap 2 #:background dark
    (text #:id composite-title "COMPOSITE WORKLIST FIXTURE")
    (settings-form #:id composite-settings #:gap 2 #:padding 2 #:background dark
      (form-row #:id sample-row
                #:label "SAMPLE INTERVAL" #:state sample-interval #:max-chars 3 #:tab-index 0
                #:on-enter apply-all #:on-apply apply-sample-interval #:placeholder "SEC" #:apply-label "Apply")
      (form-row #:id alert-row
                #:label "ALERT THRESHOLD" #:state alert-threshold #:max-chars 3 #:tab-index 1
                #:on-enter apply-all #:on-apply apply-alert-threshold #:placeholder "PCT" #:apply-label "Apply")
      (form-row #:id batch-row
                #:label "BATCH SIZE" #:state batch-size #:max-chars 3 #:tab-index 2
                #:on-enter apply-all #:on-apply apply-batch-size #:placeholder "N" #:apply-label "Apply"))
    (row #:id composite-actions #:gap 8
      (multi-field-event #:id fuse-commit #:transaction apply-all #:operation commit #:width 180 #:height 12 "Fuse Commit")
      (multi-field-event #:id fuse-reset #:transaction apply-all #:operation reset #:width 180 #:height 12 "Fuse Reset"))))
