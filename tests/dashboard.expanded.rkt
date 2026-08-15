(module dashboard noir/ui/main
  (#%module-begin
   (module configure-runtime '#%kernel
     (#%module-begin (#%require racket/runtime-config) (#%app configure '#f)))
   (define-values
    (app-scene)
    (#%app
     scene2
     (#%app
      ui-node1
      'column
      'dashboard
      (#%app hash '#:background 'dark '#:padding '24 '#:gap '16)
      (#%app
       list
       (#%app
        ui-node1
        'text
        'title
        (#%app hash 'value '"NOIR GPU DASHBOARD")
        (#%app list)
        '#<path:/home/ubuntu/noir_review/noir-racket-ui/examples/dashboard.rkt>)
       (#%app
        ui-node1
        'row
        'metrics
        (#%app hash '#:gap '12)
        (#%app
         list
         (#%app
          ui-node1
          'text
          'fps
          (#%app hash 'value '(dynamic frame-rate) 'max-chars '3)
          (#%app list)
          '#<path:/home/ubuntu/noir_review/noir-racket-ui/examples/dashboard.rkt>)
         (#%app
          ui-node1
          'text
          'latency
          (#%app hash 'value '"ms")
          (#%app list)
          '#<path:/home/ubuntu/noir_review/noir-racket-ui/examples/dashboard.rkt>))
        '#<path:/home/ubuntu/noir_review/noir-racket-ui/examples/dashboard.rkt>)
       (#%app
        ui-node1
        'button
        'refresh
        (#%app hash 'on 'refresh-data 'label '"Refresh")
        (#%app list)
        '#<path:/home/ubuntu/noir_review/noir-racket-ui/examples/dashboard.rkt>))
      '#<path:/home/ubuntu/noir_review/noir-racket-ui/examples/dashboard.rkt>)
     '5
     '1
     '#hash((glyph_capacity . 3) (instance_capacity . 6) (node_capacity . 6))
     '((glyph-patch fps 3))))
   (#%provide app-scene)))
