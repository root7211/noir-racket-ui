#lang racket/base

(require racket/list
         (only-in "../examples/dashboard.rkt" app-scene)
         "../noir/ui/main.rkt")

(define schedule (first (scene-render-schedules app-scene)))
(displayln
 (list 'actions
       (for/list ([plan (in-list (scene-actions app-scene))])
         (list (action-plan-id plan) (action-plan-tile-ids plan)))))
(displayln
 (list 'frame-tasks
       (for/list ([task (in-list (scene-frame-schedule app-scene))])
         (list (frame-task-id task) (frame-task-kind task) (frame-task-tile-ids task)))))
(for ([tile (in-list (render-schedule-tiles schedule))] [tile-id (in-naturals)])
  (displayln
   (list 'tile tile-id
         (list (render-tile-x tile) (render-tile-y tile)
               (render-tile-width tile) (render-tile-height tile))
         (render-tile-selected-strategy tile)
         (for/list ([range (in-list (render-tile-glyph-packet-ranges tile))])
           (list (glyph-packet-range-packet-index range)
                 (glyph-packet-range-first-placement range)
                 (glyph-packet-range-placement-count range))))))
