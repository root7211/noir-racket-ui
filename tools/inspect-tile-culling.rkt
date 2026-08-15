#lang racket/base

(require racket/list
         (only-in "../examples/dashboard.rkt" app-scene)
         "../noir/ui/main.rkt")

(define schedule (first (scene-render-schedules app-scene)))
(for ([tile (in-list (render-schedule-tiles schedule))] [index (in-naturals)])
  (displayln
   (list 'tile index
         'rect (list (render-tile-x tile) (render-tile-y tile)
                     (render-tile-width tile) (render-tile-height tile))
         'strategy (render-tile-selected-strategy tile)
         'fallback (render-tile-fallback-reason tile)
         'draw-first (map draw-range-first-instance (render-tile-draw-ranges tile))
         'draw-count (map draw-range-instance-count (render-tile-draw-ranges tile))
         'glyph-ranges
         (for/list ([range (in-list (render-tile-glyph-packet-ranges tile))])
           (list (glyph-packet-range-packet-id range)
                 (glyph-packet-range-packet-index range)
                 (glyph-packet-range-first-placement range)
                 (glyph-packet-range-placement-count range)
                 (glyph-packet-range-bounds range)
                 (glyph-packet-range-dynamic? range))))))
(displayln (list 'coverage (render-schedule-coverage schedule)))
(displayln (list 'packet-bounds (map glyph-draw-packet-bounds (scene-glyph-draw-packets app-scene))))
