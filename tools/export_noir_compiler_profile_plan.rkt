#lang racket

(require json)

(define (usage)
  (raise-user-error 'export_noir_compiler_profile_plan
                    "usage: racket tools/export_noir_compiler_profile_plan.rkt SCENE OUTPUT"))

(define (field object key)
  (define symbol-key (string->symbol key))
  (cond [(hash-has-key? object key) (hash-ref object key)]
        [(hash-has-key? object symbol-key) (hash-ref object symbol-key)]
        [else (raise-user-error 'export_noir_compiler_profile_plan "missing Scene key ~a" key)]))

(define (profile-for systems alerts)
  (define tuple (list (field systems "logical_capacity") (field systems "physical_slots")
                      (field alerts "logical_capacity") (field alerts "physical_slots")))
  (cond [(equal? tuple '(10000 4 2048 3)) "standard"]
        [(equal? tuple '(2048 3 512 3)) "compact"]
        [else (raise-user-error 'export_noir_compiler_profile_plan "unsupported bounded profile ~a" tuple)]))

(define (project-data-view entry)
  (hasheq 'id (field entry "id")
          'list_id (field entry "list_id")
          'owner_view_id (field entry "view_id")
          'list_index (field entry "list_index")
          'logical_capacity (field entry "logical_capacity")
          'physical_slots (field entry "physical_slots")
          'visible_rows (field entry "visible_rows")
          'scrollbar_id (field entry "scrollbar_id")
          'navigation_id (field entry "navigation_id")
          'log_browser_id (field entry "log_browser_id")
          'row_activation_action (field entry "row_activation_action")))

(module+ main
  (define args (current-command-line-arguments))
  (unless (= (vector-length args) 2) (usage))
  (define scene-path (vector-ref args 0))
  (define output-path (vector-ref args 1))
  (define scene (call-with-input-file scene-path read-json))
  (define workbench (field scene "material_observability_workbench_plan"))
  (define data-views (field workbench "data_views"))
  (unless (= (length data-views) 2)
    (raise-user-error 'export_noir_compiler_profile_plan "expected exactly two data views"))
  (define systems (first data-views))
  (define alerts (second data-views))
  (define app-id (regexp-replace #rx"-workbench$" (field workbench "id") ""))
  (define transaction (field scene "workbench_cross_view_transaction_plan"))
  (define acknowledged (field scene "acknowledged_row_state_plan"))
  (define projection
    (hasheq
     'app_id app-id
     'profile (profile-for systems alerts)
     'workbench
     (hasheq 'id (field workbench "id")
             'rail_id (field workbench "rail_id")
             'initial_value (field workbench "initial_value")
             'views (for/list ([view (in-list (field workbench "views"))])
                      (hasheq 'id (field view "view_root_id") 'value (field view "target_value")))
             'data_views (map project-data-view data-views))
     'transaction
     (hasheq 'id (field transaction "id")
             'action_id (field transaction "action_id")
             'action_slot_index (field transaction "action_slot_index")
             'state_id (field transaction "state")
             'state_index (field transaction "state_index")
             'delta (field transaction "delta")
             'source_data_view_id (field transaction "source_data_view_id")
             'source_list_id (field transaction "source_list_id")
             'source_view_id (field transaction "source_view_id")
             'target_view_id (field transaction "target_view_id"))
     'acknowledged_row_state
     (hasheq 'id (field acknowledged "id")
             'data_view_id (field acknowledged "data_view_id")
             'list_id (field acknowledged "list_id")
             'owner_view_id (field acknowledged "owner_view_id")
             'logical_capacity (field acknowledged "logical_capacity")
             'state_domain (field acknowledged "state_domain")
             'word_bits (field acknowledged "word_bits")
             'word_count (field acknowledged "word_count")
             'acknowledge_action_id (field acknowledged "acknowledge_action_id")
             'action_slot_index (field acknowledged "action_slot_index"))))
  (call-with-output-file output-path
    (lambda (out) (write-json projection out) (newline out))
    #:exists 'truncate/replace)
  (printf "NOIR_COMPILER_RACKET_PROFILE: PASS scene=~a output=~a\n" scene-path output-path))
