#lang noir/ui

;; The only resource-policy choice visible to the application author is a named
;; compile-time profile; no raw capacity or physical-slot value is accepted.
(noir-workbench/app
 #:id operations-compact
 #:title "Compact operations workbench"
 #:profile compact
 (systems #:seed "INFO  TIME  CORE  STARTUP")
 (alerts #:seed "WARN  TIME  EDGE  RETRY" #:row-state acknowledged))
