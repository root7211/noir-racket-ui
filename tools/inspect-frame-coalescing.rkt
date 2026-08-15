#lang racket/base

(require racket/list
         (only-in "../examples/dashboard.rkt" app-scene)
         "../noir/ui/main.rkt")

(for ([batch (in-list (scene-frame-coalesced-batches app-scene))])
  (displayln
   (list 'batch
         (frame-coalesced-batch-id batch)
         'tasks (frame-coalesced-batch-task-ids batch)
         'order (frame-coalesced-batch-execution-order batch)
         'winner-writes
         (for/list ([write (in-list (frame-coalesced-batch-winner-writes batch))])
           (list (frame-coalesced-write-task-id write)
                 (frame-coalesced-write-offset write)
                 (frame-coalesced-write-byte-length write)))
         'eliminated
         (for/list ([item (in-list (frame-coalesced-batch-eliminated-writes batch))])
           (list (frame-coalesced-elimination-task-id item)
                 (frame-coalesced-elimination-offset item)
                 (frame-coalesced-elimination-byte-length item)
                 (frame-coalesced-elimination-winner item)))
         'tiles (frame-coalesced-batch-merged-tile-ids batch)
         'edges
         (for/list ([edge (in-list (frame-coalesced-batch-conflict-edges batch))])
           (list (conflict-edge-left edge) (conflict-edge-right edge)
                 (conflict-edge-winner edge))))))
