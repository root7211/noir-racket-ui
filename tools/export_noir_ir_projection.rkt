#lang racket

(require json)

(define (usage)
  (raise-user-error 'export_noir_ir_projection
                    "usage: racket tools/export_noir_ir_projection.rkt SCENE OUTPUT"))

(define (field object key)
  (define symbol-key (string->symbol key))
  (cond [(hash-has-key? object key) (hash-ref object key)]
        [(hash-has-key? object symbol-key) (hash-ref object symbol-key)]
        [else (raise-user-error 'export_noir_ir_projection "missing canonical Scene key ~a" key)]))

(define (object object keys)
  (for/hasheq ([key (in-list keys)])
    (values (string->symbol key) (field object key))))

(define contract-keys '("schema" "revision"))
(define view-keys '("destination_id" "view_root_id" "target_value" "tile_ids"))
(define data-view-keys
  '("id" "list_id" "view_id" "list_index" "logical_capacity" "physical_slots"
    "visible_rows" "scrollbar_id" "navigation_id" "log_browser_id"
    "row_activation_action" "tile_ids"))
(define transaction-keys
  '("id" "action_id" "action_slot_index" "delta" "event_slot"
    "source_data_view_id" "source_list_id" "source_view_id"
    "source_row_color_offsets" "source_detail_glyph_offsets" "state" "state_index"
    "target_view_id" "target_count_glyph_offsets" "tile_ids"))
(define acknowledged-keys
  '("id" "data_view_id" "list_id" "owner_view_id" "logical_capacity"
    "state_domain" "word_bits" "word_count" "acknowledge_action_id"
    "action_slot_index" "row_color_offsets" "detail_glyph_offsets" "tile_ids"))

(define (project-workbench workbench)
  (hasheq
   'schema (field workbench "abi_schema")
   'revision (field workbench "abi_revision")
   'id (field workbench "id")
   'rail_id (field workbench "rail_id")
   'initial_value (field workbench "initial_value")
   'views (for/list ([entry (in-list (field workbench "views"))]) (object entry view-keys))
   'data_views (for/list ([entry (in-list (field workbench "data_views"))]) (object entry data-view-keys))))

(define (project-transaction transaction)
  (define base (object transaction transaction-keys))
  (hash-set* base
             'schema (field transaction "abi_schema")
             'revision (field transaction "abi_revision")))

(define (project-acknowledged acknowledged)
  (define base (object acknowledged acknowledged-keys))
  (hash-set* base
             'schema (field acknowledged "abi_schema")
             'revision (field acknowledged "abi_revision")))

(module+ main
  (define args (current-command-line-arguments))
  (unless (= (vector-length args) 2) (usage))
  (define scene-path (vector-ref args 0))
  (define output-path (vector-ref args 1))
  (define scene (call-with-input-file scene-path read-json))
  (define contracts (field scene "abi_contracts"))
  (define projection
    (hasheq
     'contracts
     (hasheq
      'workbench (object (field contracts "material_observability_workbench_plan") contract-keys)
      'transaction (object (field contracts "workbench_cross_view_transaction_plan") contract-keys)
      'acknowledged_row_state (object (field contracts "acknowledged_row_state_plan") contract-keys))
     'workbench (project-workbench (field scene "material_observability_workbench_plan"))
     'transaction (project-transaction (field scene "workbench_cross_view_transaction_plan"))
     'acknowledged_row_state (project-acknowledged (field scene "acknowledged_row_state_plan"))))
  (call-with-output-file output-path
    (lambda (out) (write-json projection out) (newline out))
    #:exists 'truncate/replace)
  (printf "NOIR_IR_RACKET_PROJECT: PASS scene=~a output=~a\n" scene-path output-path))
