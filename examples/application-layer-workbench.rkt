#lang noir/ui

;; Application layer v1: no capacity, physical-slot, state-owner, stable internal
;; ID, workbench data-view or cross-view transaction declaration is authored here.
(noir-workbench/app
 #:id operations
 #:title "Operations workbench"
 (systems #:seed "INFO  TIME  CORE  STARTUP")
 (alerts #:seed "WARN  TIME  EDGE  RETRY"))
