#lang racket/base

(require json
         (only-in "../examples/alpha_overlay_dashboard.rkt" app-scene)
         "../noir/ui/main.rkt")

(define output
  (or (and (= (vector-length (current-command-line-arguments)) 1)
           (vector-ref (current-command-line-arguments) 0))
      "out/alpha.scene.json"))

(call-with-output-file output
  (lambda (port)
    (write-json (scene->jsexpr app-scene) port))
  #:exists 'truncate/replace)
