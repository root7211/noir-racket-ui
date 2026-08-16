#lang racket/base

;; #lang noir/ui 的核心语言。
;; reader 只把模块交给本文件；真正的 DSL parser 是 hygienic macro。
;; `ui` 在展开期将布局语法解析为 Scene IR，并生成一个纯数据 scene 值。

(require json
         racket/list
         racket/match
         racket/pretty
         racket/set
         syntax/parse/define
         (for-syntax racket/base
                     racket/list
                     racket/match
                     racket/set
                     racket/string
                     racket/port
                     racket/file
                     racket/path
                     json
                     syntax/parse))

(provide (all-from-out racket/base)
         ui
         noir-app
         scene?
         scene-root
         scene-static-node-count
         scene-dynamic-node-count
         scene-resource-budget
         scene-update-plan
         scene-state
         scene-state-slots
         scene-actions
         scene-action-slots
scene-transactions
          scene-command-matchers
          scene-layout-plan
         scene-glyph-placement-plan
scene-glyph-draw-packets
          scene-subgroup-packet-plan
          scene-packet-activity-contract
          scene-packet-worklists
          scene-event-map
         scene-animation-tracks
         scene-frame-schedule
         scene-conflict-graph
         scene-frame-coalesced-batches
         scene-render-schedules
         scene-focus-graph
         scene-keyboard-map
         scene-keyboard-command-map
         scene-virtual-list-plans
         scene-log-browser-plans
         scene-font-assets
         scene-shadow-surface-plan
         (struct-out shadow-surface)
         (struct-out shadow-surface-plan)
         (struct-out virtual-list-plan)
         (struct-out log-browser-plan)
         (struct-out font-asset-plan)
         (struct-out render-schedule)
         (struct-out render-tile)
         (struct-out draw-range)
         (struct-out frame-task)
         (struct-out conflict-edge)
         (struct-out frame-coalesced-write)
         (struct-out frame-coalesced-elimination)
         (struct-out frame-coalesced-batch)
         (struct-out batch-task-ref)
         (struct-out animation-track)
         (struct-out event-binding)
         (struct-out action-plan)
         (struct-out action-slot)
         (struct-out transaction-plan)
         (struct-out command-matcher)
         (struct-out state-slot)
         (struct-out state-write)
         (struct-out gpu-update)
         (struct-out instance-update)
         (struct-out damage-region)
         (struct-out glyph-placement)
         (struct-out glyph-draw-packet)
         (struct-out glyph-packet-range)
         (struct-out subgroup-packet)
         (struct-out packet-activity-contract)
         (struct-out packet-worklist)
         (struct-out focus-entry)
         (struct-out focus-graph)
(struct-out digit-register)
           (struct-out ascii-text-register)
           (struct-out keyboard-field)
          (struct-out keyboard-transition)
          (struct-out keyboard-map)
         (struct-out keyboard-command-transition)
         (struct-out keyboard-command-map)
         scene->jsexpr
         write-scene-json
         print-scene-plan
         compile-scene->wgpu-plan)

;; ------------------------------ Runtime IR ------------------------------

;; Frozen compiler-to-host interfaces.  A future incompatible evolution must
;; allocate a new schema/revision rather than make the host infer semantics.
(define virtual-list-plan-abi-schema "noir-virtual-list-plan-v1")
(define virtual-list-plan-abi-revision 1)
(define row-activation-plan-abi-schema "noir-row-activation-plan-v1")
(define row-activation-plan-abi-revision 1)
(define scrollbar-plan-abi-schema "noir-scrollbar-plan-v1")
(define scrollbar-plan-abi-revision 1)
(define list-navigation-plan-abi-schema "noir-list-navigation-plan-v1")
(define list-navigation-plan-abi-revision 1)
;; Application-level artifact. It references the frozen list plans but never rewrites them.
(define log-browser-plan-abi-schema "noir-log-browser-plan-v1")
(define log-browser-plan-abi-revision 1)
(define font-asset-plan-abi-schema "noir-font-asset-plan-v1")
(define font-asset-plan-abi-revision 1)
;; font_asset_plan v1 remains a registration/byte-integrity contract. This distinct
;; placement contract activates its atlas only for compiler-proved static page-2 runs.
(define font-placement-plan-abi-schema "noir-font-placement-plan-v1")
(define font-placement-plan-abi-revision 1)
;; Dynamic table-body cells use a separate page-3 contract. It never relaxes
;; static page-2 placement semantics or legacy page 0/1 registration.
(define dynamic-font-cell-plan-abi-schema "noir-dynamic-font-cell-plan-v1")
(define dynamic-font-cell-plan-abi-revision 1)
;; Visual language v1 fixes the compile-time canvas used by layout/NDC/tile lowering.
(define visual-language-plan-abi-schema "noir-visual-language-plan-v1")
(define visual-language-plan-abi-revision 1)
;; Rounded surface metadata is a parallel immutable table indexed by the frozen
;; 44-byte QuadInstance slot; it never mutates the QuadInstance ABI itself.
(define rounded-surface-plan-abi-schema "noir-rounded-surface-plan-v1")
(define rounded-surface-plan-abi-revision 1)
;; Shadow metadata is a distinct immutable render pass. It stores fully expanded
;; physical rectangles and never adds mutable instance slots to the UI Scene.
(define shadow-surface-plan-abi-schema "noir-shadow-surface-plan-v1")
(define shadow-surface-plan-abi-revision 1)

(define (abi-contracts->jsexpr)
  (hash 'virtual_list_plan
        (hash 'schema virtual-list-plan-abi-schema
              'revision virtual-list-plan-abi-revision)
        'row_activation_plan
        (hash 'schema row-activation-plan-abi-schema
              'revision row-activation-plan-abi-revision)
        'scrollbar_plan
        (hash 'schema scrollbar-plan-abi-schema
              'revision scrollbar-plan-abi-revision)
        'list_navigation_plan
        (hash 'schema list-navigation-plan-abi-schema
              'revision list-navigation-plan-abi-revision)
        'log_browser_plan
        (hash 'schema log-browser-plan-abi-schema
              'revision log-browser-plan-abi-revision)
        'font_asset_plan
        (hash 'schema font-asset-plan-abi-schema
              'revision font-asset-plan-abi-revision)
        'font_placement_plan
        (hash 'schema font-placement-plan-abi-schema
              'revision font-placement-plan-abi-revision)
        'dynamic_font_cell_plan
        (hash 'schema dynamic-font-cell-plan-abi-schema
              'revision dynamic-font-cell-plan-abi-revision)
        'visual_language_plan
        (hash 'schema visual-language-plan-abi-schema
              'revision visual-language-plan-abi-revision)
        'rounded_surface_plan
        (hash 'schema rounded-surface-plan-abi-schema
              'revision rounded-surface-plan-abi-revision)
        'shadow_surface_plan
        (hash 'schema shadow-surface-plan-abi-schema
              'revision shadow-surface-plan-abi-revision)))

(struct ui-node (tag id props children source) #:transparent)
;; Scene 以静态树和增量执行计划共同组成。state/actions 由 `noir-app`
;; 的扩展语法生成；普通 `(ui ...)` 保持空状态表，仍可独立使用。
(struct scene (root static-node-count dynamic-node-count resource-budget state state-slots actions action-slots transactions command-matchers update-plan layout-plan glyph-placement-plan glyph-draw-packets subgroup-packet-plan packet-activity-contract packet-worklists event-map animation-tracks frame-schedule conflict-graph frame-coalesced-batches render-schedules focus-graph keyboard-map keyboard-command-map virtual-list-plans row-activation-plans scrollbar-plans list-navigation-plans log-browser-plans font-assets dynamic-font-cell-plan visual-language-plan rounded-surface-plan shadow-surface-plan) #:transparent)
;; state-slot 的 index 是所有 runtime state read/write 的唯一地址；id/initial 只保留为启动期 proof 与可审计导出。
(struct state-slot (index id initial) #:transparent)
;; action-slot 与 state-slot 一样为 macro expansion 生成的 dense canonical address。
(struct action-slot (index id) #:transparent)
;; transaction-plan 仅保存 compiler 已固定的 field/state slot 对与 tile union。
(struct transaction-plan (index id field-slots state-indices tile-ids) #:transparent)
;; Command matcher 是 compiler-emitted `(cursor-length, packed-u64)` 到 Action Slot 的有限表。
(struct command-matcher (field focus-slot literal length packed action action-index tile-ids) #:transparent)
(struct state-write (state state-index op value) #:transparent)
(struct gpu-update (kind node state state-index offset byte-length glyph-count glyph-id-offsets) #:transparent)
;; instance-update 的 offset 指向 QuadInstance 内单字段；MVP 的 progress 仅更新 size.x。
(struct instance-update (kind node state state-index offset byte-length field scale) #:transparent)
(struct damage-region (kind node x y width height instance-offset) #:transparent)
;; Glyph Placement Plan 是逐字形的后端输入：NDC quad、atlas UV、storage cell、
;; clip/z/batch 均在宏展开期固定。dynamic? 只表示 glyph_id cell 可由 action 覆写。
(struct glyph-placement (slot node glyph-index glyph-id atlas-page glyph-byte-offset glyph-word-offset
                              ndc-pos ndc-size atlas-uv advance dynamic? state state-index
                              clip-stack-id clip-rect z-layer batch-key face-id) #:transparent)
;; Draw Packet 压缩相邻 placement；它是后端未来用 indirect/multi-draw 消费的静态 recipe。
(struct glyph-draw-packet (id atlas-page first-placement placement-count first-glyph-byte-offset glyph-byte-length
                               nodes bounds clip-stack-id clip-rect z-layer batch-key dynamic?) #:transparent)
;; Tile 只提交 compiler 已筛选的连续 placement subrange；packet-index 是 `glyph-draw-packets` 的稳定地址。
(struct glyph-packet-range (packet-id packet-index first-placement placement-count bounds dynamic?) #:transparent)
;; 一个 subgroup packet 对应编译期固定的 lane→placement 连续映射；width=32 是 Noir 当前 profile 的 canonical execution shape。
(struct subgroup-packet (index packet-id packet-index first-placement lane-count subgroup-width active-lane-mask activity-word-offset indirect-byte-offset dynamic?) #:transparent)
;; 两个 WGSL backend 必须消费此完全相同的 descriptor/offset ABI；变体差异仅限 lane reduction 指令。
(struct packet-activity-contract (packet-count workgroup-size scalar-entry subgroup-entry differential-required?) #:transparent)
;; worklist 的 packet-indices 是 compiler 给出的 dense activity dispatch 地址；宿主不可按 glyph/state 搜索重建。
(struct packet-worklist (index id packet-indices) #:transparent)
;; Event Map 同时携带按钮瞬态视觉状态。所有值来自编译期 Layout Plan，
;; host 只能写 base/hover/pressed 对应的固定 instance fields。
(struct event-binding (slot node action action-index transaction-op transaction-index x y width height z-index instance-offset
                            base-color hover-color pressed-color base-pos pressed-pos) #:transparent)
;; 一个轨道精确描述同一 instance 的 pos/color 从 pressed 回到 base 的时钟驱动写入。
(struct animation-track (id node instance-offset pos-offset color-offset duration-ms easing
                            pos-from pos-to color-from color-to damage) #:transparent)
;; frame-task 是 scheduler 的显式写集；conflict-edge 记录重叠字节范围和确定 winner。
(struct frame-task (id kind priority writes tile-ids packet-worklist-index packet-worklist-indices) #:transparent)
(struct conflict-edge (left right winner overlaps) #:transparent)
;; Coalesced Batch 以 compiler winner 语义替代 runtime task 排序和冲突检测。
;; winner/eliminated 均为细粒度 byte segment，可表达部分重叠的 field 写入。
(struct frame-coalesced-write (task-id offset byte-length) #:transparent)
(struct frame-coalesced-elimination (task-id offset byte-length winner) #:transparent)
(struct batch-task-ref (kind index id) #:transparent)
(struct frame-coalesced-batch (id task-ids execution-order execution-refs winner-writes eliminated-writes merged-tile-ids conflict-edges strategy-id candidate-costs selection-proof composite-worklist-index composite-worklist-member-indices composite-worklist-packet-indices fusion-baseline-requests) #:transparent)
;; Render schedule 将一帧的 Damage Plan 降低为局部 scissor tile，或在覆盖率过高时显式降级整屏。
(struct draw-range (first-instance instance-count vertex-count batch-key z-layer clip-stack-id clip-rect blend-mode opaque?) #:transparent)
(struct render-tile (x y width height nodes draw-ranges glyph-packet-ranges fallback-reason selected-strategy candidate-costs) #:transparent)
(struct render-schedule (id task-ids tiles coverage full-redraw? profile-id) #:transparent)
(struct action-plan (id action-index writes gpu-updates instance-updates damage tile-ids) #:transparent)
;; Focus Graph 完全由 compiler 生成：slot 和 next/previous 是稳定数组索引，tile-ids 是
;; 既有 render schedule 的固定地址。Host 收到 Tab 后不能排序、查询或重新计算 damage。
(struct focus-entry (slot node state state-index tab-index next-slot previous-slot tile-ids instance-offset) #:transparent)
(struct focus-graph (entries initial-slot) #:transparent)
;; Digit Register 是每个固定容量数字 field 的无字符串 pending-value 契约。
;; append: value' = value * radix + digit；drop: value' = quotient(value, radix)。
;; cursor 与 glyph slots 仍是独立的固定地址，故 host 不需要解析或重构文本。
(struct digit-register (radix max-digits initial-value reset-value maximum-value) #:transparent)
;; Uppercase ASCII register 使用固定字节槽而非十进制累计值。初值/复位均是最多 8 byte 的 packed u64。
(struct ascii-text-register (charset max-chars initial-packed reset-packed atlas-page) #:transparent)
;; Keyboard Map 在编译期显式列出受限 key transitions。cursor 是 host 侧的固定容量整数，
;; glyph-id-offsets/tile-ids 与 register arithmetic 均由 compiler 固定，按键路径不查询 UI tree。
(struct keyboard-field (focus-slot node state state-index max-chars charset glyph-id-offsets tile-ids digit-register ascii-text-register) #:transparent)
(struct keyboard-transition (focus-slot key kind glyph-id cursor-op tile-ids register-op register-radix register-operand) #:transparent)
(struct keyboard-map (fields transitions) #:transparent)
(struct keyboard-command-transition (focus-slot key kind action action-index transaction-index target-state target-state-index tile-ids) #:transparent)
(struct keyboard-command-map (transitions) #:transparent)
;; virtual-list-plan is a fully static viewport artifact. `row_layout_offsets` and
;; `visible_tile_ids` are fixed compiler addresses; runtime scroll code must select
;; from this table rather than walk a row tree or solve layout.
(struct virtual-scroll-transition (from-slot to-slot visible-row-tile-ids instance-y-patches glyph-y-patches glyph-id-patches scissor) #:transparent)
(struct virtual-list-plan (id capacity logical-capacity physical-slots recycling? logical-data-ids logical-labels initial-ring-slots data-register-table data-update-batches visible-rows row-height viewport-height row-ids row-layout-offsets row-instance-offsets row-glyph-slots row-draw-ranges row-glyph-subranges visible-tile-ids scroll-transitions) #:transparent)
;; Fully resolved by the later Action Slot Resolution Pass; runtime only indexes this proof.
(struct row-activation-plan (list-id action-id action-slot-index activate-batch-id tile-mask packet-worklist-index strategy-id physical-slot-rule) #:transparent)
;; Scrollbar Plan owns only input geometry and the fixed thumb instance address. It references,
;; but never extends or rewrites, the frozen virtual-list-plan geometry/ring ABI.
(struct scrollbar-plan (id list-id track-id thumb-id track-instance-offset thumb-instance-offset track-x track-y track-width track-height thumb-height max-viewport tile-ids packet-worklist-index physical-slot-rule) #:transparent)
;; A four-key viewport transition table. It only references frozen list/scrollbar plans.
(struct list-navigation-plan (id list-id scrollbar-id page-step max-viewport transitions tile-ids packet-worklist-index physical-slot-rule) #:transparent)
;; Application-level selected-row details and fixed tail append recipe. This is intentionally
;; separate from virtual-list-plan v1 so the list ABI remains frozen.
(struct log-browser-plan (id list-id append-batch-id append-indices append-updates detail-node-id detail-glyph-offsets detail-tile-ids row-color-offsets levels packet-worklist-index) #:transparent)
;; A v1 asset is uploaded and startup-proved but registered inactive until a later
;; placement plan explicitly targets atlas page 2 with fontc UV/metrics.
(struct font-asset-plan (face-id manifest-path atlas-path font-sha256 atlas-sha256 atlas-width atlas-height atlas-channels pixel-size line-height glyph-domain-first glyph-domain-count atlas-page activation) #:transparent)
;; Independent page-3 resource and fixed cell write authority. `tables` contains
;; plain compiler-emitted hashes: no runtime font registry or lookup is exposed.
(struct dynamic-font-cell-plan (face-id manifest-path atlas-path font-sha256 atlas-sha256 atlas-width atlas-height atlas-channels coverage-policy advance-policy fixed-advance glyph-domain-first glyph-domain-count tables) #:transparent)
;; Window dimensions are fixed compiler-owned geometry; host may configure but cannot infer them.
(struct visual-language-plan (preset width height margin) #:transparent)
;; A rounded surface is immutable shader metadata for one static QuadInstance slot.
;; It stores physical geometry as a reverse-proof witness; runtime consumes only
;; [radius, aa-width, width, height] indexed by instance_offset / 44.
(struct rounded-surface (id instance-offset x y width height radius-px aa-width-px) #:transparent)
(struct rounded-surface-plan (aa-width-px surfaces) #:transparent)
;; Each entry is one compiler-selected, expanded SDF shadow layer. `source-id` and
;; `source-instance-offset` are reverse-proof witnesses; runtime never follows them.
(struct shadow-surface (id source-id source-instance-offset elevation layer x y width height radius-px blur-px opacity) #:transparent)
(struct shadow-surface-plan (surfaces) #:transparent)

(define (value->jsexpr v)
  (cond
    [(symbol? v) (symbol->string v)]
    [(keyword? v) (keyword->string v)]
    [(pair? v) (map value->jsexpr v)]
    [(vector? v) (map value->jsexpr (vector->list v))]
    [(hash? v) (for/hash ([(k x) (in-hash v)])
                 ;; Racket 的 jsexpr object 使用 symbol 作为 key；write-json
                 ;; 负责将其编码为 JSON object key。
                 (values (if (symbol? k) k (string->symbol (format "~a" k)))
                         (value->jsexpr x)))]
    [else v]))

(define (node->jsexpr n)
  (hash 'tag (symbol->string (ui-node-tag n))
        'id (symbol->string (ui-node-id n))
        'props (value->jsexpr (ui-node-props n))
        'children (map node->jsexpr (ui-node-children n))))

(define (font-asset-plan->jsexpr plan)
  (hash 'abi_schema font-asset-plan-abi-schema
        'abi_revision font-asset-plan-abi-revision
        'face_id (font-asset-plan-face-id plan)
        'renderer_kind "atlas-gray"
        'manifest_path (font-asset-plan-manifest-path plan)
        'atlas_path (font-asset-plan-atlas-path plan)
        'font_sha256 (font-asset-plan-font-sha256 plan)
        'atlas_sha256 (font-asset-plan-atlas-sha256 plan)
        'atlas_width (font-asset-plan-atlas-width plan)
        'atlas_height (font-asset-plan-atlas-height plan)
        'atlas_channels (font-asset-plan-atlas-channels plan)
        'pixel_size (font-asset-plan-pixel-size plan)
        'line_height (font-asset-plan-line-height plan)
        'glyph_domain_first (font-asset-plan-glyph-domain-first plan)
        'glyph_domain_count (font-asset-plan-glyph-domain-count plan)
        'atlas_page (font-asset-plan-atlas-page plan)
        'activation (font-asset-plan-activation plan)))

(define (state-slot->jsexpr slot)
  (hash 'index (state-slot-index slot)
        'id (symbol->string (state-slot-id slot))
        'initial (state-slot-initial slot)))

(define (action-slot->jsexpr slot)
  (hash 'index (action-slot-index slot)
        'id (symbol->string (action-slot-id slot))))

(define (transaction-plan->jsexpr plan)
  (hash 'index (transaction-plan-index plan)
        'id (symbol->string (transaction-plan-id plan))
        'field_slots (transaction-plan-field-slots plan)
        'state_indices (transaction-plan-state-indices plan)
        'tile_ids (transaction-plan-tile-ids plan)))

(define (command-matcher->jsexpr matcher)
  (hash 'field (symbol->string (command-matcher-field matcher))
        'focus_slot (command-matcher-focus-slot matcher)
        'literal (command-matcher-literal matcher)
        'length (command-matcher-length matcher)
        'packed (command-matcher-packed matcher)
        'action (symbol->string (command-matcher-action matcher))
        'action_index (command-matcher-action-index matcher)
        'tile_ids (command-matcher-tile-ids matcher)))

(define (state-write->jsexpr w)
  (hash 'state (symbol->string (state-write-state w))
        'state_index (state-write-state-index w)
        'op (symbol->string (state-write-op w))
        'value (state-write-value w)))

(define (gpu-update->jsexpr u)
  (hash 'kind (symbol->string (gpu-update-kind u))
        'node (symbol->string (gpu-update-node u))
        'state (symbol->string (gpu-update-state u))
        'state_index (gpu-update-state-index u)
        'offset (gpu-update-offset u)
        'byte_length (gpu-update-byte-length u)
        'glyph_count (gpu-update-glyph-count u)
        'glyph_id_offsets (gpu-update-glyph-id-offsets u)))

(define (instance-update->jsexpr update)
  (hash 'kind (symbol->string (instance-update-kind update))
        'node (symbol->string (instance-update-node update))
        'state (symbol->string (instance-update-state update))
        'state_index (instance-update-state-index update)
        'offset (instance-update-offset update)
        'byte_length (instance-update-byte-length update)
        'field (symbol->string (instance-update-field update))
        'scale (instance-update-scale update)))

(define (damage-region->jsexpr damage)
  (hash 'kind (symbol->string (damage-region-kind damage))
        'node (symbol->string (damage-region-node damage))
        'x (damage-region-x damage)
        'y (damage-region-y damage)
        'width (damage-region-width damage)
        'height (damage-region-height damage)
        'instance_offset (damage-region-instance-offset damage)))

(define (glyph-placement->jsexpr placement)
  (hash 'slot (glyph-placement-slot placement)
        'node (symbol->string (glyph-placement-node placement))
        'glyph_index (glyph-placement-glyph-index placement)
        'glyph_id (glyph-placement-glyph-id placement)
        'atlas_page (glyph-placement-atlas-page placement)
        'glyph_byte_offset (glyph-placement-glyph-byte-offset placement)
        'glyph_word_offset (glyph-placement-glyph-word-offset placement)
        'ndc_pos (glyph-placement-ndc-pos placement)
        'ndc_size (glyph-placement-ndc-size placement)
        'atlas_uv (glyph-placement-atlas-uv placement)
        'advance (glyph-placement-advance placement)
        'dynamic (glyph-placement-dynamic? placement)
        'state (and (glyph-placement-state placement)
                    (symbol->string (glyph-placement-state placement)))
        'state_index (if (glyph-placement-state-index placement)
                         (glyph-placement-state-index placement)
                         'null)
        'clip_stack_id (symbol->string (glyph-placement-clip-stack-id placement))
        'clip_rect (glyph-placement-clip-rect placement)
        'z_layer (glyph-placement-z-layer placement)
        'batch_key (symbol->string (glyph-placement-batch-key placement))
        'face_id (or (glyph-placement-face-id placement) 'null)))

(define (glyph-draw-packet->jsexpr packet)
  (hash 'id (symbol->string (glyph-draw-packet-id packet))
        'atlas_page (glyph-draw-packet-atlas-page packet)
        'first_placement (glyph-draw-packet-first-placement packet)
        'placement_count (glyph-draw-packet-placement-count packet)
        'first_glyph_byte_offset (glyph-draw-packet-first-glyph-byte-offset packet)
        'glyph_byte_length (glyph-draw-packet-glyph-byte-length packet)
        'nodes (map symbol->string (glyph-draw-packet-nodes packet))
        'bounds (glyph-draw-packet-bounds packet)
        'clip_stack_id (symbol->string (glyph-draw-packet-clip-stack-id packet))
        'clip_rect (glyph-draw-packet-clip-rect packet)
        'z_layer (glyph-draw-packet-z-layer packet)
        'batch_key (symbol->string (glyph-draw-packet-batch-key packet))
        'dynamic (glyph-draw-packet-dynamic? packet)))

(define (action-plan->jsexpr action)
  (hash 'action_index (action-plan-action-index action)
        'writes (map state-write->jsexpr (action-plan-writes action))
        'gpu_updates (map gpu-update->jsexpr (action-plan-gpu-updates action))
        'instance_updates (map instance-update->jsexpr (action-plan-instance-updates action))
        'damage (map damage-region->jsexpr (action-plan-damage action))
        'tile_ids (action-plan-tile-ids action)))

(define (event-binding->jsexpr event)
  (hash 'slot (event-binding-slot event)
        'node (symbol->string (event-binding-node event))
        'action (if (event-binding-action event) (symbol->string (event-binding-action event)) 'null)
        'action_index (if (event-binding-action-index event) (event-binding-action-index event) 'null)
        'transaction_op (if (event-binding-transaction-op event) (symbol->string (event-binding-transaction-op event)) 'null)
        'transaction_index (if (event-binding-transaction-index event) (event-binding-transaction-index event) 'null)
        'x (event-binding-x event)
        'y (event-binding-y event)
        'width (event-binding-width event)
        'height (event-binding-height event)
        'z_index (event-binding-z-index event)
        'instance_offset (event-binding-instance-offset event)
        'base_color (event-binding-base-color event)
        'hover_color (event-binding-hover-color event)
        'pressed_color (event-binding-pressed-color event)
        'base_pos (event-binding-base-pos event)
        'pressed_pos (event-binding-pressed-pos event)))

(define (animation-track->jsexpr track)
  (hash 'id (symbol->string (animation-track-id track))
        'node (symbol->string (animation-track-node track))
        'instance_offset (animation-track-instance-offset track)
        'pos_offset (animation-track-pos-offset track)
        'color_offset (animation-track-color-offset track)
        'duration_ms (animation-track-duration-ms track)
        'easing (symbol->string (animation-track-easing track))
        'pos_from (animation-track-pos-from track)
        'pos_to (animation-track-pos-to track)
        'color_from (animation-track-color-from track)
        'color_to (animation-track-color-to track)
        'damage (damage-region->jsexpr (animation-track-damage track))))

(define (frame-write->jsexpr write)
  (hash 'offset (first write) 'byte_length (second write)))

(define (frame-task->jsexpr task)
  (hash 'id (symbol->string (frame-task-id task))
        'kind (symbol->string (frame-task-kind task))
        'priority (frame-task-priority task)
        'writes (map frame-write->jsexpr (frame-task-writes task))
        'tile_ids (frame-task-tile-ids task)
        'packet_worklist_index (frame-task-packet-worklist-index task)
        'packet_worklist_indices (frame-task-packet-worklist-indices task)))

(define (frame-coalesced-write->jsexpr write)
  (hash 'task_id (symbol->string (frame-coalesced-write-task-id write))
        'offset (frame-coalesced-write-offset write)
        'byte_length (frame-coalesced-write-byte-length write)))

(define (frame-coalesced-elimination->jsexpr eliminated)
  (hash 'task_id (symbol->string (frame-coalesced-elimination-task-id eliminated))
        'offset (frame-coalesced-elimination-offset eliminated)
        'byte_length (frame-coalesced-elimination-byte-length eliminated)
        'winner (symbol->string (frame-coalesced-elimination-winner eliminated))))

(define (batch-task-ref->jsexpr ref)
  (hash 'kind (symbol->string (batch-task-ref-kind ref))
        'index (batch-task-ref-index ref)
        'id (symbol->string (batch-task-ref-id ref))))

(define (frame-coalesced-batch->jsexpr batch)
  (hash 'id (symbol->string (frame-coalesced-batch-id batch))
        'task_ids (map symbol->string (frame-coalesced-batch-task-ids batch))
        'execution_order (map symbol->string (frame-coalesced-batch-execution-order batch))
        'execution_refs (map batch-task-ref->jsexpr (frame-coalesced-batch-execution-refs batch))
        'winner_writes (map frame-coalesced-write->jsexpr (frame-coalesced-batch-winner-writes batch))
        'eliminated_writes (map frame-coalesced-elimination->jsexpr (frame-coalesced-batch-eliminated-writes batch))
        'merged_tile_ids (frame-coalesced-batch-merged-tile-ids batch)
        'conflict_edges (map conflict-edge->jsexpr (frame-coalesced-batch-conflict-edges batch))
        'strategy_id (symbol->string (frame-coalesced-batch-strategy-id batch))
        'candidate_costs (value->jsexpr (frame-coalesced-batch-candidate-costs batch))
        'selection_proof (value->jsexpr (frame-coalesced-batch-selection-proof batch))
        'composite_worklist_index (frame-coalesced-batch-composite-worklist-index batch)
        'composite_worklist_member_indices (frame-coalesced-batch-composite-worklist-member-indices batch)
        'composite_worklist_packet_indices (frame-coalesced-batch-composite-worklist-packet-indices batch)
        'batch_fusion_proof
        (if (> (length (frame-coalesced-batch-composite-worklist-member-indices batch)) 1)
            (hash 'member_worklist_indices (frame-coalesced-batch-composite-worklist-member-indices batch)
                  'fused_worklist_index (frame-coalesced-batch-composite-worklist-index batch)
                  'fused_packet_indices (frame-coalesced-batch-composite-worklist-packet-indices batch)
                  'fused_tile_ids (frame-coalesced-batch-merged-tile-ids batch)
                  'baseline_requests
                  (map (lambda (request)
                         (hash 'worklist_index (first request)
                               'tile_ids (second request)))
                       (frame-coalesced-batch-fusion-baseline-requests batch))
                  'strategy_id (symbol->string (frame-coalesced-batch-strategy-id batch)))
            'null)))

(define (conflict-edge->jsexpr edge)
  (hash 'left (symbol->string (conflict-edge-left edge))
        'right (symbol->string (conflict-edge-right edge))
        'winner (symbol->string (conflict-edge-winner edge))
        'overlaps (map frame-write->jsexpr (conflict-edge-overlaps edge))))

(define (draw-range->jsexpr range)
  (hash 'first_instance (draw-range-first-instance range)
        'instance_count (draw-range-instance-count range)
        'vertex_count (draw-range-vertex-count range)
        'batch_key (symbol->string (draw-range-batch-key range))
        'z_layer (draw-range-z-layer range)
        'clip_stack_id (symbol->string (draw-range-clip-stack-id range))
        'clip_rect (draw-range-clip-rect range)
        'blend_mode (symbol->string (draw-range-blend-mode range))
        'opaque (draw-range-opaque? range)))

(define (glyph-packet-range->jsexpr range)
  (hash 'packet_id (symbol->string (glyph-packet-range-packet-id range))
        'packet_index (glyph-packet-range-packet-index range)
        'first_placement (glyph-packet-range-first-placement range)
        'placement_count (glyph-packet-range-placement-count range)
        'bounds (glyph-packet-range-bounds range)
        'dynamic (glyph-packet-range-dynamic? range)))

(define (packet-worklist->jsexpr worklist)
  (hash 'index (packet-worklist-index worklist)
        'id (symbol->string (packet-worklist-id worklist))
        'packet_indices (packet-worklist-packet-indices worklist)))

(define (packet-activity-contract->jsexpr contract)
  (hash 'packet_count (packet-activity-contract-packet-count contract)
        'workgroup_size (packet-activity-contract-workgroup-size contract)
        'scalar_entry (symbol->string (packet-activity-contract-scalar-entry contract))
        'subgroup_entry (symbol->string (packet-activity-contract-subgroup-entry contract))
        'differential_required (packet-activity-contract-differential-required? contract)))

(define (subgroup-packet->jsexpr packet)
  (hash 'index (subgroup-packet-index packet)
        'packet_id (symbol->string (subgroup-packet-packet-id packet))
        'packet_index (subgroup-packet-packet-index packet)
        'first_placement (subgroup-packet-first-placement packet)
        'lane_count (subgroup-packet-lane-count packet)
        'subgroup_width (subgroup-packet-subgroup-width packet)
        'active_lane_mask (subgroup-packet-active-lane-mask packet)
        'activity_word_offset (subgroup-packet-activity-word-offset packet)
        'indirect_byte_offset (subgroup-packet-indirect-byte-offset packet)
        'dynamic (subgroup-packet-dynamic? packet)))

(define (render-tile->jsexpr tile)
  (hash 'x (render-tile-x tile)
        'y (render-tile-y tile)
        'width (render-tile-width tile)
         'height (render-tile-height tile)
         'nodes (map symbol->string (render-tile-nodes tile))
         'draw_ranges (map draw-range->jsexpr (render-tile-draw-ranges tile))
         'glyph_packet_ranges (map glyph-packet-range->jsexpr (render-tile-glyph-packet-ranges tile))
         'fallback_reason (symbol->string (render-tile-fallback-reason tile))
         'selected_strategy (symbol->string (render-tile-selected-strategy tile))
         'candidate_costs (for/hash ([(key value) (in-hash (render-tile-candidate-costs tile))])
                            (values key value))))

(define (render-schedule->jsexpr schedule)
  (hash 'id (symbol->string (render-schedule-id schedule))
        'task_ids (map symbol->string (render-schedule-task-ids schedule))
        'tiles (map render-tile->jsexpr (render-schedule-tiles schedule))
        'coverage (render-schedule-coverage schedule)
        'full_redraw (render-schedule-full-redraw? schedule)
        'profile_id (render-schedule-profile-id schedule)))

(define (focus-entry->jsexpr entry)
  (hash 'slot (focus-entry-slot entry)
        'node (symbol->string (focus-entry-node entry))
        'state (symbol->string (focus-entry-state entry))
        'state_index (focus-entry-state-index entry)
        'tab_index (focus-entry-tab-index entry)
        'next_slot (focus-entry-next-slot entry)
        'previous_slot (focus-entry-previous-slot entry)
        'tile_ids (focus-entry-tile-ids entry)
        'instance_offset (focus-entry-instance-offset entry)))

(define (focus-graph->jsexpr graph)
  (hash 'entries (map focus-entry->jsexpr (focus-graph-entries graph))
        'initial_slot (focus-graph-initial-slot graph)))

(define (digit-register->jsexpr register)
  (hash 'radix (digit-register-radix register)
        'max_digits (digit-register-max-digits register)
        'initial_value (digit-register-initial-value register)
        'reset_value (digit-register-reset-value register)
        'maximum_value (digit-register-maximum-value register)))

(define (keyboard-field->jsexpr field)
  (hash 'focus_slot (keyboard-field-focus-slot field)
        'node (symbol->string (keyboard-field-node field))
        'state (symbol->string (keyboard-field-state field))
        'state_index (keyboard-field-state-index field)
        'max_chars (keyboard-field-max-chars field)
        'glyph_id_offsets (keyboard-field-glyph-id-offsets field)
        'tile_ids (keyboard-field-tile-ids field)
        'charset (symbol->string (keyboard-field-charset field))
        'digit_register (if (keyboard-field-digit-register field) (digit-register->jsexpr (keyboard-field-digit-register field)) 'null)
        'ascii_text_register
        (if (keyboard-field-ascii-text-register field)
            (let ([register (keyboard-field-ascii-text-register field)])
              (hash 'charset (symbol->string (ascii-text-register-charset register))
                    'max_chars (ascii-text-register-max-chars register)
                    'initial_packed (ascii-text-register-initial-packed register)
                    'reset_packed (ascii-text-register-reset-packed register)
                    'atlas_page (ascii-text-register-atlas-page register)))
            'null)))

(define (keyboard-transition->jsexpr transition)
  (hash 'focus_slot (keyboard-transition-focus-slot transition)
        'key (symbol->string (keyboard-transition-key transition))
        'kind (symbol->string (keyboard-transition-kind transition))
        'glyph_id (keyboard-transition-glyph-id transition)
        'cursor_op (symbol->string (keyboard-transition-cursor-op transition))
        'tile_ids (keyboard-transition-tile-ids transition)
        'register_op (symbol->string (keyboard-transition-register-op transition))
        'register_radix (keyboard-transition-register-radix transition)
        'register_operand (keyboard-transition-register-operand transition)))

(define (keyboard-map->jsexpr kmap)
  (hash 'fields (map keyboard-field->jsexpr (keyboard-map-fields kmap))
        'transitions (map keyboard-transition->jsexpr (keyboard-map-transitions kmap))))

(define (keyboard-command-map->jsexpr command-map)
  (hash 'transitions
        (for/list ([transition (in-list (keyboard-command-map-transitions command-map))])
          (hash 'focus_slot (keyboard-command-transition-focus-slot transition)
                'key (symbol->string (keyboard-command-transition-key transition))
                'kind (symbol->string (keyboard-command-transition-kind transition))
                'action (if (keyboard-command-transition-action transition)
                            (symbol->string (keyboard-command-transition-action transition))
                            'null)
                'action_index (if (keyboard-command-transition-action-index transition)
                                  (keyboard-command-transition-action-index transition)
                                  'null)
                'transaction_index (if (keyboard-command-transition-transaction-index transition)
                                       (keyboard-command-transition-transaction-index transition)
                                       'null)
                'target_state (if (keyboard-command-transition-target-state transition)
                                  (symbol->string (keyboard-command-transition-target-state transition))
                                  'null)
                'target_state_index (if (keyboard-command-transition-target-state-index transition)
                                        (keyboard-command-transition-target-state-index transition)
                                        'null)
                'tile_ids (keyboard-command-transition-tile-ids transition)))))

(define (text-field-visuals->jsexpr s)
  ;; 所有坐标、instance field 地址和 blink 参数来自已经宏展开的 Layout/Focus 产物。
  ;; Host 只使用这些数组；它不再测量 glyph advance、field rect 或 derived child ID。
  (define layouts (for/hash ([layout (in-list (scene-layout-plan s))])
                    (values (hash-ref layout 'id) layout)))
  (for/list ([entry (in-list (focus-graph-entries (scene-focus-graph s)))])
    (define node (focus-entry-node entry))
    (define focus-id (string->symbol (format "~a$focus" node)))
    (define placeholder-id (string->symbol (format "~a$placeholder" node)))
    (define caret-id (string->symbol (format "~a$caret" node)))
    (define field-layout (hash-ref layouts node))
    (define focus-layout (hash-ref layouts focus-id))
    (define placeholder-layout (hash-ref layouts placeholder-id))
    (define caret-layout (hash-ref layouts caret-id))
    (define max-chars (hash-ref field-layout 'glyph_count))
    (define caret-x (hash-ref caret-layout 'x))
    (define cell-advance (/ (hash-ref field-layout 'width) max-chars))
    (hash 'focus_slot (focus-entry-slot entry)
          'node (symbol->string node)
          'tile_ids (focus-entry-tile-ids entry)
          'max_chars max-chars
          'focus_instance_offset (hash-ref focus-layout 'instance_offset)
          'focus_alpha_offset (+ (hash-ref focus-layout 'instance_offset) 28)
          'placeholder_instance_offset (hash-ref placeholder-layout 'instance_offset)
          'placeholder_alpha_offset (+ (hash-ref placeholder-layout 'instance_offset) 28)
          'caret_instance_offset (hash-ref caret-layout 'instance_offset)
          'caret_pos_x_offset (hash-ref caret-layout 'instance_offset)
          'caret_alpha_offset (+ (hash-ref caret-layout 'instance_offset) 28)
          'caret_x_positions (for/list ([cursor (in-range (+ max-chars 1))])
                               (+ caret-x (* cursor cell-advance)))
          'caret_ndc_x_positions (for/list ([cursor (in-range (+ max-chars 1))])
                                   (- (* 2.0 (/ (+ caret-x (* cursor cell-advance)) 640.0)) 1.0))
          'blink_track (hash 'id (format "~a-caret-blink" node)
                             'period_ms 500
                             'alpha '(1.0 0.0)))))

(define (virtual-list-plan->jsexpr plan)
  (hash 'abi_schema virtual-list-plan-abi-schema
        'abi_revision virtual-list-plan-abi-revision
        'id (symbol->string (virtual-list-plan-id plan))
        'capacity (virtual-list-plan-capacity plan)
        'logical_capacity (virtual-list-plan-logical-capacity plan)
        'physical_slots (virtual-list-plan-physical-slots plan)
        'recycling (virtual-list-plan-recycling? plan)
        'logical_data_ids (map symbol->string (virtual-list-plan-logical-data-ids plan))
        'logical_labels (virtual-list-plan-logical-labels plan)
        'initial_ring_slots (virtual-list-plan-initial-ring-slots plan)
        'data_register_table (value->jsexpr (virtual-list-plan-data-register-table plan))
        'data_update_batches (value->jsexpr (virtual-list-plan-data-update-batches plan))
        'visible_rows (virtual-list-plan-visible-rows plan)
        'row_height (virtual-list-plan-row-height plan)
        'viewport_height (virtual-list-plan-viewport-height plan)
        'row_ids (map symbol->string (virtual-list-plan-row-ids plan))
        'row_layout_offsets (virtual-list-plan-row-layout-offsets plan)
        'row_instance_offsets (virtual-list-plan-row-instance-offsets plan)
        'row_glyph_slots (virtual-list-plan-row-glyph-slots plan)
        'row_draw_ranges (virtual-list-plan-row-draw-ranges plan)
        'row_glyph_subranges (virtual-list-plan-row-glyph-subranges plan)
        'visible_row_tile_ids (virtual-list-plan-visible-tile-ids plan)
        'scroll_transitions
        (for/list ([transition (in-list (virtual-list-plan-scroll-transitions plan))])
          (hash 'from_slot (virtual-scroll-transition-from-slot transition)
                'to_slot (virtual-scroll-transition-to-slot transition)
                'visible_row_tile_ids (virtual-scroll-transition-visible-row-tile-ids transition)
                'instance_y_patches (virtual-scroll-transition-instance-y-patches transition)
                'glyph_y_patches (virtual-scroll-transition-glyph-y-patches transition)
                'glyph_id_patches (virtual-scroll-transition-glyph-id-patches transition)
                'scissor (virtual-scroll-transition-scissor transition)))))

(define (scrollbar-plan->jsexpr plan)
  (hash 'abi_schema scrollbar-plan-abi-schema
        'abi_revision scrollbar-plan-abi-revision
        'id (symbol->string (scrollbar-plan-id plan))
        'list_id (symbol->string (scrollbar-plan-list-id plan))
        'track_id (symbol->string (scrollbar-plan-track-id plan))
        'thumb_id (symbol->string (scrollbar-plan-thumb-id plan))
        'track_instance_offset (scrollbar-plan-track-instance-offset plan)
        'thumb_instance_offset (scrollbar-plan-thumb-instance-offset plan)
        'track (hash 'x (scrollbar-plan-track-x plan)
                     'y (scrollbar-plan-track-y plan)
                     'width (scrollbar-plan-track-width plan)
                     'height (scrollbar-plan-track-height plan))
        'thumb_height (scrollbar-plan-thumb-height plan)
        'max_viewport (scrollbar-plan-max-viewport plan)
        'tile_ids (scrollbar-plan-tile-ids plan)
        'packet_worklist_index (scrollbar-plan-packet-worklist-index plan)
        'physical_slot_rule (symbol->string (scrollbar-plan-physical-slot-rule plan))))

(define (list-navigation-plan->jsexpr plan)
  (hash 'abi_schema list-navigation-plan-abi-schema
        'abi_revision list-navigation-plan-abi-revision
        'id (symbol->string (list-navigation-plan-id plan))
        'list_id (symbol->string (list-navigation-plan-list-id plan))
        'scrollbar_id (symbol->string (list-navigation-plan-scrollbar-id plan))
        'page_step (list-navigation-plan-page-step plan)
        'max_viewport (list-navigation-plan-max-viewport plan)
        'transitions (for/list ([transition (in-list (list-navigation-plan-transitions plan))])
                       (hash 'key (symbol->string (first transition))
                             'kind (symbol->string (second transition))))
        'tile_ids (list-navigation-plan-tile-ids plan)
        'packet_worklist_index (list-navigation-plan-packet-worklist-index plan)
        'physical_slot_rule (symbol->string (list-navigation-plan-physical-slot-rule plan))))

(define (log-browser-plan->jsexpr plan)
  (hash 'abi_schema log-browser-plan-abi-schema
        'abi_revision log-browser-plan-abi-revision
        'id (symbol->string (log-browser-plan-id plan))
        'list_id (symbol->string (log-browser-plan-list-id plan))
        'append_batch_id (symbol->string (log-browser-plan-append-batch-id plan))
        'append_indices (log-browser-plan-append-indices plan)
        'append_updates (for/list ([entry (in-list (log-browser-plan-append-updates plan))])
                          (hash 'index (car entry) 'value (cdr entry)))
        'detail_node_id (symbol->string (log-browser-plan-detail-node-id plan))
        'detail_glyph_offsets (log-browser-plan-detail-glyph-offsets plan)
        'detail_tile_ids (log-browser-plan-detail-tile-ids plan)
        'row_color_offsets (log-browser-plan-row-color-offsets plan)
        'levels (value->jsexpr (log-browser-plan-levels plan))
        'packet_worklist_index (log-browser-plan-packet-worklist-index plan)))

(define (row-activation-plan->jsexpr plan)
  (hash 'abi_schema row-activation-plan-abi-schema
        'abi_revision row-activation-plan-abi-revision
        'list_id (symbol->string (row-activation-plan-list-id plan))
        'action_id (symbol->string (row-activation-plan-action-id plan))
        'action_slot_index (row-activation-plan-action-slot-index plan)
        'activate_batch_id (symbol->string (row-activation-plan-activate-batch-id plan))
        'tile_mask (row-activation-plan-tile-mask plan)
        'packet_worklist_index (row-activation-plan-packet-worklist-index plan)
        'strategy_id (symbol->string (row-activation-plan-strategy-id plan))
        'physical_slot_rule (symbol->string (row-activation-plan-physical-slot-rule plan))))

(define (list-interaction-plan->jsexpr plan)
  (hash 'id (symbol->string (virtual-list-plan-id plan))
        'logical_capacity (virtual-list-plan-logical-capacity plan)
        'physical_slots (virtual-list-plan-physical-slots plan)
        'visible_rows (virtual-list-plan-visible-rows plan)
        'row_height (virtual-list-plan-row-height plan)
        ;; QuadInstance color starts at byte 16; runtime may only patch these compiler addresses.
        'row_color_offsets (map (lambda (offset) (+ offset 16)) (virtual-list-plan-row-layout-offsets plan))
'hover_color '(0.10 0.17 0.25 1.0)
         'selected_color '(0.16 0.25 0.38 1.0)
        'navigation (hash 'up_delta -1 'down_delta 1
                          'minimum_logical_row 0
                          'maximum_logical_row (sub1 (virtual-list-plan-logical-capacity plan)))
        'render (hash 'packet_worklist_index 2
                      'viewport_only #t
                      'row_tile_rule "logical-mod-physical-slots")))

(define (dynamic-font-cell-plan->jsexpr plan)
  (and plan
       (hash 'abi_schema dynamic-font-cell-plan-abi-schema
             'abi_revision dynamic-font-cell-plan-abi-revision
             'face_id (dynamic-font-cell-plan-face-id plan)
             'manifest_path (dynamic-font-cell-plan-manifest-path plan)
             'atlas_path (dynamic-font-cell-plan-atlas-path plan)
             'font_sha256 (dynamic-font-cell-plan-font-sha256 plan)
             'atlas_sha256 (dynamic-font-cell-plan-atlas-sha256 plan)
             'atlas_width (dynamic-font-cell-plan-atlas-width plan)
             'atlas_height (dynamic-font-cell-plan-atlas-height plan)
             'atlas_channels (dynamic-font-cell-plan-atlas-channels plan)
             'atlas_page 3
             'coverage_policy (dynamic-font-cell-plan-coverage-policy plan)
             'advance_policy (dynamic-font-cell-plan-advance-policy plan)
             'fixed_advance (dynamic-font-cell-plan-fixed-advance plan)
             'glyph_domain_first (dynamic-font-cell-plan-glyph-domain-first plan)
             'glyph_domain_count (dynamic-font-cell-plan-glyph-domain-count plan)
             'tables (value->jsexpr (dynamic-font-cell-plan-tables plan)))))

(define (visual-language-plan->jsexpr plan)
  (hash 'abi_schema visual-language-plan-abi-schema
        'abi_revision visual-language-plan-abi-revision
        'preset (symbol->string (visual-language-plan-preset plan))
        'canvas (hash 'width (visual-language-plan-width plan)
                      'height (visual-language-plan-height plan)
                      'margin (visual-language-plan-margin plan))))

(define (rounded-surface-plan->jsexpr plan)
  (and plan
       (hash 'abi_schema rounded-surface-plan-abi-schema
             'abi_revision rounded-surface-plan-abi-revision
             'aa_width_px (rounded-surface-plan-aa-width-px plan)
             'surfaces
             (for/list ([surface (in-list (rounded-surface-plan-surfaces plan))])
               (hash 'id (symbol->string (rounded-surface-id surface))
                     'instance_offset (rounded-surface-instance-offset surface)
                     'x (rounded-surface-x surface)
                     'y (rounded-surface-y surface)
                     'width (rounded-surface-width surface)
                     'height (rounded-surface-height surface)
                     'radius_px (rounded-surface-radius-px surface)
                     'aa_width_px (rounded-surface-aa-width-px surface))))))

(define (shadow-surface-plan->jsexpr plan)
  (and plan
       (hash 'abi_schema shadow-surface-plan-abi-schema
             'abi_revision shadow-surface-plan-abi-revision
             'layers
             (for/list ([surface (in-list (shadow-surface-plan-surfaces plan))])
               (hash 'id (symbol->string (shadow-surface-id surface))
                     'source_id (symbol->string (shadow-surface-source-id surface))
                     'source_instance_offset (shadow-surface-source-instance-offset surface)
                     'elevation (shadow-surface-elevation surface)
                     'layer (shadow-surface-layer surface)
                     'x (shadow-surface-x surface)
                     'y (shadow-surface-y surface)
                     'width (shadow-surface-width surface)
                     'height (shadow-surface-height surface)
                     'radius_px (shadow-surface-radius-px surface)
                     'blur_px (shadow-surface-blur-px surface)
                     'opacity (shadow-surface-opacity surface))))))

(define (scene->jsexpr s #:build-attestation [build-attestation #f])
  (define base
    (hash 'abi_contracts (abi-contracts->jsexpr)
        'root (node->jsexpr (scene-root s))
        'static_node_count (scene-static-node-count s)
        'dynamic_node_count (scene-dynamic-node-count s)
        'resource_budget (value->jsexpr (scene-resource-budget s))
        'state (value->jsexpr (scene-state s))
        'state_slots (map state-slot->jsexpr (scene-state-slots s))
        'actions (for/hash ([action (in-list (scene-actions s))])
                   (values (action-plan-id action) (action-plan->jsexpr action)))
        'action_slots (map action-slot->jsexpr (scene-action-slots s))
        'transactions (map transaction-plan->jsexpr (scene-transactions s))
         'command_matchers (map command-matcher->jsexpr (scene-command-matchers s))
         'update_plan (value->jsexpr (scene-update-plan s))
        'layout_plan (value->jsexpr (scene-layout-plan s))
        'glyph_placement_plan (map glyph-placement->jsexpr (scene-glyph-placement-plan s))
        'glyph_draw_packets (map glyph-draw-packet->jsexpr (scene-glyph-draw-packets s))
         'subgroup_packet_plan (map subgroup-packet->jsexpr (scene-subgroup-packet-plan s))
         'packet_activity_contract (packet-activity-contract->jsexpr (scene-packet-activity-contract s))
         'packet_worklists (map packet-worklist->jsexpr (scene-packet-worklists s))
         'event_map (map event-binding->jsexpr (scene-event-map s))
        'animation_tracks (map animation-track->jsexpr (scene-animation-tracks s))
        'frame_schedule (map frame-task->jsexpr (scene-frame-schedule s))
        'conflict_graph (map conflict-edge->jsexpr (scene-conflict-graph s))
        'frame_coalesced_batches (map frame-coalesced-batch->jsexpr (scene-frame-coalesced-batches s))
        'render_schedules (map render-schedule->jsexpr (scene-render-schedules s))
        'focus_graph (focus-graph->jsexpr (scene-focus-graph s))
        'keyboard_map (keyboard-map->jsexpr (scene-keyboard-map s))
        'keyboard_command_map (keyboard-command-map->jsexpr (scene-keyboard-command-map s))
        'virtual_list_plans (map virtual-list-plan->jsexpr (scene-virtual-list-plans s))
        'list_interaction_plans (map list-interaction-plan->jsexpr (scene-virtual-list-plans s))
        'row_activation_plans (map row-activation-plan->jsexpr (scene-row-activation-plans s))
        'scrollbar_plans (map scrollbar-plan->jsexpr (scene-scrollbar-plans s))
        'list_navigation_plans (map list-navigation-plan->jsexpr (scene-list-navigation-plans s))
        'log_browser_plans (map log-browser-plan->jsexpr (scene-log-browser-plans s))
        'font_assets (map font-asset-plan->jsexpr (scene-font-assets s))
        'dynamic_font_cell_plan (dynamic-font-cell-plan->jsexpr (scene-dynamic-font-cell-plan s))
        'visual_language_plan (visual-language-plan->jsexpr (scene-visual-language-plan s))
        'rounded_surface_plan (rounded-surface-plan->jsexpr (scene-rounded-surface-plan s))
        'shadow_surface_plan (shadow-surface-plan->jsexpr (scene-shadow-surface-plan s))
        'text_field_visuals (text-field-visuals->jsexpr s)))
  (if build-attestation
      (hash-set base 'build_attestation (value->jsexpr build-attestation))
      base))

(define (write-scene-json s out #:build-attestation [build-attestation #f])
  (write-json (scene->jsexpr s #:build-attestation build-attestation) out))

(define (print-scene-plan s [out (current-output-port)])
  (fprintf out "Noir UI plan\n")
  (fprintf out "  static nodes : ~a\n" (scene-static-node-count s))
  (fprintf out "  dynamic nodes: ~a\n" (scene-dynamic-node-count s))
  (fprintf out "  resource budget: ~s\n" (scene-resource-budget s))
  (for ([step (in-list (scene-update-plan s))])
    (fprintf out "  ~s\n" step))
  (for ([action (in-list (scene-actions s))])
    (fprintf out "  action ~a: ~s\n" (action-plan-id action) (action-plan-gpu-updates action)))
  (fprintf out "  layout instances: ~a\n" (length (scene-layout-plan s)))
  (fprintf out "  glyph placements: ~a; glyph packets: ~a\n"
           (length (scene-glyph-placement-plan s)) (length (scene-glyph-draw-packets s)))
  (fprintf out "  event bindings: ~a\n" (length (scene-event-map s)))
  (fprintf out "  animation tracks: ~a\n" (length (scene-animation-tracks s)))
  (fprintf out "  scheduled tasks: ~a; conflicts: ~a\n"
           (length (scene-frame-schedule s)) (length (scene-conflict-graph s)))
  (fprintf out "  render schedules: ~a\n" (length (scene-render-schedules s)))
  (fprintf out "  focus entries: ~a; keyboard transitions: ~a\n"
           (length (focus-graph-entries (scene-focus-graph s)))
           (length (keyboard-map-transitions (scene-keyboard-map s)))))

;; 后端无关产物。Nelua/C/Rust runtime 可把它降低为 wgpu 的 atlas、
;; instance buffers 与固定 render recipe；本 demo 不绑定 wgpu FFI。
(define (compile-scene->wgpu-plan s)
  (hash 'pipelines '(quad-sdf glyph-atlas image)
        'instance-buffer 'ui-instance-buffer
        'glyph-buffer 'glyph-instance-buffer
        'resource-budget (scene-resource-budget s)
        'state (scene-state s)
        'actions (scene-actions s)
        'updates (scene-update-plan s)
        'layout-plan (scene-layout-plan s)
        'glyph-placement-plan (scene-glyph-placement-plan s)
        'glyph-draw-packets (scene-glyph-draw-packets s)
        'virtual-list-plans (scene-virtual-list-plans s)
        'scrollbar-plans (scene-scrollbar-plans s)
        'event-map (scene-event-map s)
        'animation-tracks (scene-animation-tracks s)
        'frame-schedule (scene-frame-schedule s)
        'conflict-graph (scene-conflict-graph s)
        'render-schedules (scene-render-schedules s)
        'focus-graph (scene-focus-graph s)
        'keyboard-map (scene-keyboard-map s)
        'shadow-surface-plan (scene-shadow-surface-plan s)))

;; -------------------------- Expand-time parser ---------------------------

(begin-for-syntax
  (struct c-node (tag id props children source) #:transparent)
  (struct c-state (id initial source) #:transparent)
  (struct c-action (id state op value source) #:transparent)
  ;; state 为 #f 表示编译期静态 shaped text；glyph-ids/advances/page 是后端可直接消费的资源计划。
  (struct c-binding (node-id state mutable? offset byte-length glyph-count atlas-page glyph-ids glyph-advances face-id) #:transparent)
  ;; progress 的 value 不触发 layout solve，而是映射到预分配 QuadInstance 的 size.x。
  (struct c-instance-binding (node-id state max-value layout) #:transparent)
  (struct c-event (slot node-id action action-index action-ids transaction-op transaction-index x y width height z-index instance-offset
                        base-color hover-color pressed-color base-pos pressed-pos) #:transparent)
  (struct c-animation (id event duration-ms easing) #:transparent)
  ;; tile-ids 在 Task Selection pass 后填充；它是 runtime 唯一允许使用的 tile 地址表。
  (struct c-frame-task (id kind priority writes tile-ids packet-worklist-index packet-worklist-indices) #:transparent)
  (struct c-conflict (left right winner overlaps) #:transparent)
  (struct c-coalesced-write (task-id offset byte-length) #:transparent)
  (struct c-coalesced-elimination (task-id offset byte-length winner) #:transparent)
  (struct c-coalesced-batch (id task-ids execution-order winner-writes eliminated-writes merged-tile-ids conflict-edges strategy-id candidate-costs selection-proof composite-worklist-index composite-worklist-member-indices composite-worklist-packet-indices fusion-baseline-requests) #:transparent)
  (struct c-rect (node x y width height) #:transparent)
  (struct c-draw-range (first-instance instance-count vertex-count batch-key z-layer clip-stack-id clip-rect blend-mode opaque?) #:transparent)
  (struct c-render-tile (x y width height nodes draw-ranges glyph-packet-ranges fallback-reason selected-strategy candidate-costs) #:transparent)
  (struct c-partition (composites fallback-reason) #:transparent)
  (struct c-render-schedule (id task-ids tiles coverage full-redraw? profile-id) #:transparent)
  (struct c-virtual-scroll-transition (from-slot to-slot visible-row-tile-ids instance-y-patches glyph-y-patches glyph-id-patches scissor) #:transparent)
  (struct c-virtual-list-plan (id capacity logical-capacity physical-slots recycling? logical-data-ids logical-labels initial-ring-slots data-register-table data-update-batches visible-rows row-height viewport-height row-ids row-layout-offsets row-instance-offsets row-glyph-slots row-draw-ranges row-glyph-subranges visible-tile-ids scroll-transitions) #:transparent)
  (struct c-scrollbar-plan (id list-id track-id thumb-id track-instance-offset thumb-instance-offset track-x track-y track-width track-height thumb-height max-viewport tile-ids packet-worklist-index physical-slot-rule) #:transparent)
  (struct c-list-navigation-spec (id list-id scrollbar-id source) #:transparent)
  (struct c-list-navigation-plan (id list-id scrollbar-id page-step max-viewport transitions tile-ids packet-worklist-index physical-slot-rule) #:transparent)
  ;; Application-only spec: list and detail glyph addresses are resolved after layout.
  (struct c-log-browser-spec (id list-id detail-id append-updates source) #:transparent)
  (struct c-log-browser-plan (id list-id append-batch-id append-updates detail-node-id detail-glyph-offsets detail-tile-ids row-color-offsets levels packet-worklist-index) #:transparent)
  (struct c-font-asset-spec (manifest-path atlas-path source) #:transparent)
  (struct c-font-glyph (glyph-id codepoint character x y width height advance bearing-x bearing-y) #:transparent)
(struct c-font-asset-plan (face-id manifest-path atlas-path font-sha256 atlas-sha256 atlas-width atlas-height atlas-channels pixel-size line-height glyph-domain-first glyph-domain-count atlas-page activation glyphs) #:transparent)
   ;; Kept separate from c-font-asset-plan: page 3 is dynamic fixed-cell data, not
   ;; an activation mode of the static page-2 font placement ABI.
   (struct c-dynamic-font-cell-asset (face-id manifest-path atlas-path font-sha256 atlas-sha256 atlas-width atlas-height atlas-channels coverage-policy advance-policy fixed-advance glyphs source) #:transparent)
   (struct c-action-plan (id action action-index text-updates instance-updates damage tile-ids) #:transparent)
  ;; Layout Plan 是后端可直接消费的静态几何契约。instance-offset 以
  ;; QuadInstance 的 44-byte packed layout 为单位，和 Rust vertex layout 对齐。
  (struct c-layout (id tag x y width height elevation color glyph-offset glyph-count atlas-page glyph-ids glyph-advances instance-offset vertex-count) #:transparent)
  ;; Rounded metadata is emitted after layout offsets are frozen; it cannot alter
  ;; layout, event patch offsets, glyph placement or QuadInstance bytes.
  (struct c-rounded-surface (id instance-offset x y width height radius-px aa-width-px) #:transparent)
  (struct c-shadow-surface (id source-id source-instance-offset elevation layer x y width height radius-px blur-px opacity) #:transparent)
  ;; 每个 c-glyph-placement 对应一个永不重新寻址的 32-byte glyph cell，以及已落位的 NDC quad。
  ;; glyph-id 对动态数字表示 initial state；action 可以覆写该 cell 的首个 u32，但不能改变 geometry/page/packet。
  (struct c-glyph-placement (slot node-id glyph-index glyph-id atlas-page glyph-byte-offset glyph-word-offset
                                  ndc-pos ndc-size atlas-uv advance dynamic? state state-index
                                  clip-stack-id clip-rect z-layer batch-key face-id) #:transparent)
  ;; Packet 按连续 placement 的 atlas page、clip/z/batch、动态性压缩；下游可直接映射为 batch 或 indirect draw。
  (struct c-glyph-packet (id atlas-page first-placement placement-count first-glyph-byte-offset glyph-byte-length
                             nodes bounds clip-stack-id clip-rect z-layer batch-key dynamic?) #:transparent)
  (struct c-glyph-packet-range (packet-id packet-index first-placement placement-count bounds dynamic?) #:transparent)
  (struct c-subgroup-packet (index packet-id packet-index first-placement lane-count subgroup-width active-lane-mask activity-word-offset indirect-byte-offset dynamic?) #:transparent)
  (struct c-packet-activity-contract (packet-count workgroup-size scalar-entry subgroup-entry differential-required?) #:transparent)
  (struct c-packet-worklist (index id packet-indices) #:transparent)
  ;; Freshness Admission 是纯宏展开期输入；不进入 runtime Scene 或 host dispatch。
  ;; `status` 只能是 fresh/stale/inconclusive/missing/invalid，policy 为 strict 或 permissive。
  (struct c-profile-admission (policy status reason manifest diagnostic) #:transparent)
  ;; Focus Graph 在 render tile 固化后生成，形成 Tab/Shift+Tab 的稳定 slot 环路。
  (struct c-focus-entry (slot node-id state state-index tab-index next-slot previous-slot tile-ids instance-offset) #:transparent)
  (struct c-focus-graph (entries initial-slot) #:transparent)
  (struct c-digit-register (radix max-digits initial-value reset-value maximum-value) #:transparent)
  (struct c-ascii-text-register (charset max-chars initial-packed reset-packed atlas-page) #:transparent)
  (struct c-keyboard-field (focus-slot node-id state state-index max-chars charset glyph-id-offsets tile-ids digit-register ascii-text-register) #:transparent)
  (struct c-keyboard-transition (focus-slot key kind glyph-id cursor-op tile-ids register-op register-radix register-operand) #:transparent)
  (struct c-keyboard-map (fields transitions) #:transparent)
  (struct c-transaction (id states) #:transparent)
  (struct c-transaction-plan (index id field-slots state-indices tile-ids) #:transparent)
  (struct c-command-spec (field literal action) #:transparent)
  (struct c-command-matcher (field focus-slot literal length packed action action-index tile-ids) #:transparent)
  (struct c-keyboard-command-transition (focus-slot key kind action action-index transaction-index target-state target-state-index tile-ids) #:transparent)
  (struct c-keyboard-command-map (transitions) #:transparent)

  ;; ABI slots 使用 state symbol 的字典序；插入无关 source 顺序的 state 时既有 ID 的相对排序稳定且 Rust 可独立验证。
  (define (canonical-states states)
    (sort states symbol<? #:key c-state-id))

  (define (state-index-by-id states)
    (for/hash ([state (in-list (canonical-states states))] [index (in-naturals)])
      (values (c-state-id state) index)))

  (define (canonical-actions actions)
    (sort actions symbol<? #:key c-action-id))

  (define (action-index-by-id actions)
    (for/hash ([action (in-list (canonical-actions actions))] [index (in-naturals)])
      (values (c-action-id action) index)))

  (define (transaction-index-by-id transactions)
    (for/hash ([transaction (in-list (sort transactions symbol<? #:key c-transaction-id))] [index (in-naturals)])
      (values (c-transaction-id transaction) index)))

  (define glyph-instance-bytes 32)
  (define quad-instance-bytes 44)
  (define digit-atlas-page 0)
  (define ascii-atlas-page 1)

  ;; MVP shaping 是受限、确定的 ASCII glyph map：静态 label 不依赖 runtime font lookup。
  ;; page 0 保留给动态数字；page 1 覆盖空格与大写 A–Z。编码的高 16 bit 为 atlas page。
  (define (encode-glyph page glyph-id) (+ (arithmetic-shift page 16) glyph-id))
  (define (font-asset-by-face who face-id source)
    (or (findf (lambda (plan) (string=? (c-font-asset-plan-face-id plan) face-id))
               (current-static-font-assets))
        (raise-syntax-error who
                            (format "unknown #:font-face ~a; declare a matching (font-asset ...) in the same noir-app" face-id)
                            source)))

  (define (font-face-id who raw source)
    (cond [(symbol? raw) (symbol->string raw)]
          [(string? raw) raw]
          [else (raise-syntax-error who "#:font-face expects a literal symbol or string face ID" source)]))

  (define (shape-static-fontc who text face-id source)
    (unless (string? text)
      (raise-syntax-error who "fontc text must be a string literal" source))
    (define asset (font-asset-by-face who face-id source))
    (define glyph-by-codepoint
      (for/hash ([glyph (in-list (c-font-asset-plan-glyphs asset))])
        (values (c-font-glyph-codepoint glyph) glyph)))
    (define glyphs
      (for/list ([ch (in-string text)])
        (hash-ref glyph-by-codepoint (char->integer ch)
                  (lambda ()
                    (raise-syntax-error who
                                        (format "font face ~a has no compiled glyph for U+~04X" face-id (char->integer ch))
                                        source)))))
    (values (c-font-asset-plan-atlas-page asset)
            (map (lambda (glyph) (encode-glyph (c-font-asset-plan-atlas-page asset)
                                                (c-font-glyph-glyph-id glyph)))
                 glyphs)
            (map c-font-glyph-advance glyphs)
            face-id))

  (define (shape-static-ascii who text source)
    (unless (string? text)
      (raise-syntax-error who "static text must be a string literal" source))
    (define glyphs
      (for/list ([ch (in-string (string-upcase text))])
        (cond [(char=? ch #\space) 0]
              [(and (char>=? ch #\A) (char<=? ch #\Z))
               (+ 1 (- (char->integer ch) (char->integer #\A)))]
              [else
               (raise-syntax-error who
                                   (format "unsupported static glyph ~s; ASCII uppercase and space are allowed in the MVP" ch)
                                   source)])))
    (values ascii-atlas-page
            (map (lambda (glyph) (encode-glyph ascii-atlas-page glyph)) glyphs)
            (make-list (length glyphs) 1.0)
            #f))

  ;; 动态数字的几何容量已固定；这里仅把 initial state lowering 为首帧的 page-0 glyph ID。
  ;; 以后 action 只能覆写每 slot 的 glyph_id，不得改变 slot、atlas page 或 NDC placement。
  (define (shape-initial-digits who state-id initial glyph-count source)
    (unless (exact-nonnegative-integer? initial)
      (raise-syntax-error who
                          (format "dynamic numeric text state ~a must have a non-negative initial value" state-id)
                          source))
    (define raw (number->string initial))
    (when (> (string-length raw) glyph-count)
      (raise-syntax-error who
                          (format "initial value ~a exceeds fixed glyph capacity ~a" initial glyph-count)
                          source))
    (define padded (string-append (make-string (- glyph-count (string-length raw)) #\0) raw))
    (map (lambda (ch)
           (encode-glyph digit-atlas-page (- (char->integer ch) (char->integer #\0))))
         (string->list padded)))

  ;; Profile 在宏展开期读取，发布后的 runtime 不读取设备信息也不自适应调参。
  (define default-cost-profile
    (hash 'profile_id "noir-static-cost-v1"
          'coefficients (hash 'draw_range_ns 600.0
                              'covered_pixel_ns 1.0
                              'clip_switch_ns 150.0
                              'full_tile_multiplier 4.0)))
  (define (profile-ref object key [fallback #f])
    (cond [(hash-has-key? object key) (hash-ref object key)]
          [(hash-has-key? object (symbol->string key)) (hash-ref object (symbol->string key))]
          [else fallback]))
  (define (profile-id=? profile requested-id)
    (and requested-id
         (equal? (profile-ref profile 'profile_id #f) requested-id)))
  (define (load-cost-profile)
    (define path (getenv "NOIR_COST_PROFILE"))
    (define requested-id (getenv "NOIR_PROFILE_ID"))
    (cond
      [(not (and path (not (string=? path "")))) default-cost-profile]
      [else
       (define raw (call-with-input-file path read-json))
       (define registry-profiles (profile-ref raw 'profiles #f))
       (cond
         [registry-profiles
          ;; Registry 必须显式指定目标 profile；未命中一律回退，避免构建时猜错设备。
          (or (findf (lambda (profile) (profile-id=? profile requested-id)) registry-profiles)
              default-cost-profile)]
         [(and requested-id (not (profile-id=? raw requested-id))) default-cost-profile]
         [else raw])]))
  (define active-cost-profile (load-cost-profile))
  (define active-profile-id (profile-ref active-cost-profile 'profile_id "noir-static-cost-v1"))
  (define active-profile-coefficients
    (profile-ref active-cost-profile 'coefficients (profile-ref default-cost-profile 'coefficients)))
  (define (profile-coefficient key)
    (profile-ref active-profile-coefficients key
                 (profile-ref (profile-ref default-cost-profile 'coefficients) key)))

  ;; Replay Matrix profile 只允许比较同一完整视觉语义组。`action-aware` 省略 release
  ;; 视觉写入，故绝不进入 complete activate 的自动 strategy 候选集。
  (define replay-semantic-group "complete-activate-v1")
  (define replay-strategy-order '(full-redraw packet-aware coalesced))
  (define (profile-string=? value expected)
    (and value (string=? (format "~a" value) expected)))
  (define (replay-profile-batch batch-id)
    (define replay (profile-ref active-cost-profile 'replay_strategy_costs #f))
    (and replay
         (findf (lambda (entry)
                  (profile-string=? (profile-ref entry 'batch_id #f) (symbol->string batch-id)))
                (profile-ref replay 'batches '()))))
  (define (replay-candidates-for batch-id root)
    (define replay (profile-ref active-cost-profile 'replay_strategy_costs #f))
    (define entry (replay-profile-batch batch-id))
    (cond
      [(not entry) #f]
      [else
       (unless (and (profile-string=? (profile-ref replay 'schema #f) "noir-wgpu-replay-matrix-v1")
                    (profile-string=? (profile-ref replay 'semantic_group #f) replay-semantic-group)
                    (profile-string=? (profile-ref replay 'selection_metric #f) "gpu_median_ns"))
         (raise-syntax-error 'profile "replay_strategy_costs has an unsupported schema, semantic group, or metric" (c-node-source root)))
       (define candidates
         (filter (lambda (candidate)
                   (and (profile-string=? (profile-ref candidate 'semantic_group #f) replay-semantic-group)
                        (member (string->symbol (format "~a" (profile-ref candidate 'strategy_id #f))) replay-strategy-order)))
                 (profile-ref entry 'candidates '())))
       (for ([strategy (in-list replay-strategy-order)])
         (define candidate
           (findf (lambda (item)
                    (eq? (string->symbol (format "~a" (profile-ref item 'strategy_id #f))) strategy))
                  candidates))
         (unless candidate
           (raise-syntax-error 'profile (format "replay profile for ~a omits semantic strategy ~a" batch-id strategy) (c-node-source root)))
         (define cost (profile-ref candidate 'gpu_median_ns #f))
         (unless (and (real? cost) (>= cost 0.0))
           (raise-syntax-error 'profile (format "replay profile for ~a has invalid gpu_median_ns for ~a" batch-id strategy) (c-node-source root))))
       candidates]))
  (define (choose-replay-strategy batch root)
    (define id (c-coalesced-batch-id batch))
    (if (not (regexp-match? #rx"^coalesced-activate-" (symbol->string id)))
        (struct-copy c-coalesced-batch batch
                     [strategy-id 'coalesced]
                     [candidate-costs (hash 'coalesced 0.0)]
                     [selection-proof (hash 'mode 'non-activate-batch
                                            'profile_id active-profile-id)])
        (let ([candidates (replay-candidates-for id root)])
          (if (not candidates)
              (struct-copy c-coalesced-batch batch
                           [strategy-id 'coalesced]
                           [candidate-costs (hash 'coalesced 0.0)]
                           ;; No replay profile is an explicit compile-time condition, not a
                           ;; runtime gap. Select the canonical coalesced baseline and emit
                           ;; its winner so the host can still prove executor/Scene agreement.
                           [selection-proof (hash 'mode 'profile-unavailable
                                                  'profile_id active-profile-id
                                                  'semantic_group replay-semantic-group
                                                  'selection_metric 'static-default
                                                  'winner 'coalesced)])
              (let* ([costs
                      (for/hash ([candidate (in-list candidates)])
                        (values (string->symbol (format "~a" (profile-ref candidate 'strategy_id #f)))
                                (profile-ref candidate 'gpu_median_ns)))]
                     [winner
                      (for/fold ([best (car replay-strategy-order)])
                                ([strategy (in-list (cdr replay-strategy-order))])
                        ;; 严格小于才换 winner；相等时由 replay-strategy-order 固定 tie-break。
                        (if (< (hash-ref costs strategy) (hash-ref costs best)) strategy best))])
                (struct-copy c-coalesced-batch batch
                             [strategy-id winner]
                             [candidate-costs costs]
                             [selection-proof
                              (hash 'mode 'profile-guided
                                    'profile_id active-profile-id
                                    'semantic_group replay-semantic-group
                                    'selection_metric 'gpu_median_ns
                                    'source_batch id
                                    'winner winner
                                    'tie_break_order replay-strategy-order)]))))))
  ;; Rust Freshness Gate 的结果是离线 artifact。编译器只在这里读取；事件期和 host
  ;; 不得访问这个文件、不得据此重新选择 renderer。指纹由构建器显式提供，防止把一个
  ;; calibration Scene 的证据错误嫁接给另一份输出 Scene。
  (define (admission-policy)
    (define raw (or (getenv "NOIR_PROFILE_ADMISSION") "permissive"))
    (cond [(member raw '("strict" "permissive" "bootstrap")) (string->symbol raw)]
          [else (error 'profile-admission "NOIR_PROFILE_ADMISSION must be strict, permissive, or bootstrap, got ~a" raw)]))
  (define (read-artifact path who)
    (and path (not (string=? path ""))
         (if (file-exists? path)
             (call-with-input-file path read-json)
             (error who "artifact does not exist: ~a" path))))
  (define (artifact-status value)
    (and value (string->symbol (format "~a" (profile-ref value 'status #f)))))
  (define (load-profile-admission)
    (define policy (admission-policy))
    (define manifest (read-artifact (getenv "NOIR_FRESHNESS_MANIFEST") 'profile-admission))
    (define diagnostic (read-artifact (getenv "NOIR_FRESHNESS_DIAGNOSTIC") 'profile-admission))
    (cond
      ;; bootstrap 只允许生成首次 calibration artifact；它仍由 source fingerprint 绑定，
      ;; 且 proof 显式标记该来源，不能被误认为 strict/permissive 的已验证准入。
      [(eq? policy 'bootstrap)
       (c-profile-admission policy 'fresh 'bootstrap-calibration manifest diagnostic)]
      [(or (not manifest) (not diagnostic))
       (c-profile-admission policy 'missing 'freshness-artifact-missing manifest diagnostic)]
      [(not (profile-string=? (profile-ref manifest 'schema #f) "noir-calibration-manifest-v1"))
       (c-profile-admission policy 'invalid 'manifest-schema manifest diagnostic)]
      [(not (profile-string=? (profile-ref diagnostic 'schema #f) "noir-profile-freshness-v1"))
       (c-profile-admission policy 'invalid 'diagnostic-schema manifest diagnostic)]
      [(not (profile-string=? (profile-ref manifest 'profile_id #f) active-profile-id))
       (c-profile-admission policy 'invalid 'profile-id-mismatch manifest diagnostic)]
      [(not (eq? (artifact-status diagnostic) 'fresh))
       (c-profile-admission policy (or (artifact-status diagnostic) 'invalid) 'freshness-not-fresh manifest diagnostic)]
      [else
       ;; build tool 在动态 require dashboard 前自动注入 canonical source fingerprint；
       ;; 保留旧变量仅用于过渡期的直接模块实验，正式 builder 不再要求用户手写它。
       (define expected-scene-fingerprint
         (or (getenv "NOIR_CANONICAL_SOURCE_FINGERPRINT")
             (getenv "NOIR_FRESHNESS_SCENE_FINGERPRINT")))
       (cond
         [(or (not expected-scene-fingerprint) (string=? expected-scene-fingerprint ""))
          (c-profile-admission policy 'inconclusive 'scene-fingerprint-unset manifest diagnostic)]
         [(not (profile-string=? (profile-ref manifest 'source_fingerprint_fnv1a64 #f)
                                 expected-scene-fingerprint))
          (c-profile-admission policy 'stale 'source-fingerprint-mismatch manifest diagnostic)]
         [else
          (c-profile-admission policy 'fresh 'admitted manifest diagnostic)])]))
  (define active-profile-admission (load-profile-admission))
  (define (admission-fresh? admission)
    (eq? (c-profile-admission-status admission) 'fresh))
  (define (admission-manifest-case admission batch-id)
    (and (c-profile-admission-manifest admission)
         (findf (lambda (entry)
                  (profile-string=? (profile-ref entry 'batch_id #f) (symbol->string batch-id)))
                (profile-ref (c-profile-admission-manifest admission) 'compiler_selected '()))))
  (define (admission-fallback batch reason)
    (struct-copy c-coalesced-batch batch
                 [strategy-id 'coalesced]
                 [candidate-costs (hash 'coalesced 0.0)]
                  ;; No fresh calibration may change the strategy at runtime. The
                  ;; compiler emits the canonical coalesced fallback winner together
                  ;; with the admission reason so host replay can prove the fixed path.
                  [selection-proof (hash 'mode 'profile-unavailable
                                         'profile_id active-profile-id
                                         'semantic_group replay-semantic-group
                                         'selection_metric 'static-default
                                         'winner 'coalesced
                                         'reason reason
                                         'admission_policy (c-profile-admission-policy active-profile-admission)
                                         'freshness_status (c-profile-admission-status active-profile-admission))]))
  (define (annotate-profile-admission batch)
    (define proof (c-coalesced-batch-selection-proof batch))
    (struct-copy c-coalesced-batch batch
                 [selection-proof
                  (hash-set (hash-set proof 'admission_policy (c-profile-admission-policy active-profile-admission))
                            'freshness_status (c-profile-admission-status active-profile-admission))]))
  (define (admit-replay-winner batch winner root)
    (define admission active-profile-admission)
    (define manifest-case (admission-manifest-case admission (c-coalesced-batch-id batch)))
    (define manifest-strategy (and manifest-case
                                   (string->symbol (format "~a" (profile-ref manifest-case 'strategy_id #f)))))
    (cond
      [(eq? (c-profile-admission-policy admission) 'bootstrap) #t]
      [(and (admission-fresh? admission) manifest-case (eq? manifest-strategy winner)) #t]
      [(eq? (c-profile-admission-policy admission) 'strict)
       (raise-syntax-error 'profile
                           (format "strict Profile Admission rejected ~a: status=~a reason=~a manifest-winner=~a compiler-winner=~a"
                                   (c-coalesced-batch-id batch)
                                   (c-profile-admission-status admission)
                                   (c-profile-admission-reason admission)
                                   manifest-strategy winner)
                           (c-node-source root))]
      [else #f]))
  ;; Multi-action admission is deliberately after profile selection: the proof binds
  ;; the final compiler strategy, task order, byte-conflict graph and tile partition.
  ;; Rejected batches remain normal coalesced batches; they never receive a fused packet slot.
  (define (annotate-multi-action-fusion-admission batches events tasks root)
    (define task-by-id (for/hash ([task (in-list tasks)]) (values (c-frame-task-id task) task)))
    (define action-events
      (for/hash ([event (in-list events)] #:when (> (length (c-event-action-ids event)) 1))
        (values (string->symbol (format "coalesced-activate-~a" (c-event-node-id event))) event)))
    (for/list ([batch (in-list batches)])
      (define event (hash-ref action-events (c-coalesced-batch-id batch) #f))
      (if (not event)
          batch
          (let* ([actions (c-event-action-ids event)]
                 [release-id (string->symbol (format "release-~a" (c-event-node-id event)))]
                 [action-tasks (map (lambda (id) (hash-ref task-by-id id)) actions)]
                 [action-tiles (append-map c-frame-task-tile-ids action-tasks)]
                 [action-edges (filter (lambda (edge)
                                         (and (member (c-conflict-left edge) actions)
                                              (member (c-conflict-right edge) actions)))
                                       (c-coalesced-batch-conflict-edges batch))]
                 [non-overlap? (= (length action-tiles) (length (remove-duplicates action-tiles)))]
                 [packet-safe? (andmap (lambda (task)
                                         (= (c-frame-task-packet-worklist-index task) 2))
                                       action-tasks)]
                 [release-first? (and (pair? (c-coalesced-batch-execution-order batch))
                                      (eq? (car (c-coalesced-batch-execution-order batch)) release-id))]
                 [exact-members? (equal? (c-coalesced-batch-task-ids batch)
                                         (cons release-id actions))]
                 [admitted? (and exact-members? (null? action-edges) non-overlap? packet-safe? release-first?)]
                 [proof (hash 'status (if admitted? 'admitted 'rejected)
                              'reason (cond [(not exact-members?) 'task-membership]
                                            [(not release-first?) 'animation-order]
                                            [(not (null? action-edges)) 'write-conflict]
                                            [(not non-overlap?) 'tile-overlap]
                                            [(not packet-safe?) 'packet-scope]
                                            [else 'unknown])
                              'action_ids actions
                              'release_task release-id
                              'action_tile_ids (map c-frame-task-tile-ids action-tasks)
                              'packet_worklist_indices (map c-frame-task-packet-worklist-index action-tasks)
                              'strategy_id (c-coalesced-batch-strategy-id batch)
                              'conflict_edge_count (length action-edges))])
            (when (and admitted? (not (eq? (c-coalesced-batch-strategy-id batch) 'coalesced)))
              (raise-syntax-error 'multi-action-event "multi-action fusion requires compiler coalesced strategy" (c-node-source root)))
            (struct-copy c-coalesced-batch batch
                         [selection-proof (hash-set (c-coalesced-batch-selection-proof batch)
                                                    'fusion_admission proof)])))))

  (define (compile-profile-guided-batch-strategies batches root)
    (define selected (map (lambda (batch)
                            ;; 先按 frozen profile 得到唯一候选 winner，再让 offline admission 决定
                            ;; 是否可采用该结果。permissive fallback 永远是 coalesced，绝不 runtime 自适应。
                            (define proposed (choose-replay-strategy batch root))
                            (if (not (regexp-match? #rx"^coalesced-activate-" (symbol->string (c-coalesced-batch-id batch))))
                                proposed
                                (if (eq? (hash-ref (c-coalesced-batch-selection-proof proposed) 'mode) 'profile-guided)
                                    (if (admit-replay-winner proposed (c-coalesced-batch-strategy-id proposed) root)
                                        (annotate-profile-admission proposed)
                                        (admission-fallback proposed (c-profile-admission-reason active-profile-admission)))
                                    (if (eq? (c-profile-admission-policy active-profile-admission) 'strict)
                                        (raise-syntax-error 'profile
                                                            (format "strict Profile Admission has no admissible replay profile for ~a (status=~a reason=~a)"
                                                                    (c-coalesced-batch-id batch)
                                                                    (c-profile-admission-status active-profile-admission)
                                                                    (c-profile-admission-reason active-profile-admission))
                                                            (c-node-source root))
                                        (admission-fallback proposed (c-profile-admission-reason active-profile-admission))))))
                          batches))
    ;; 最终 proof：完整 activate 只能选择同语义的三个策略之一，winner 必为候选最小值。
    (for ([batch (in-list selected)])
      (when (regexp-match? #rx"^coalesced-activate-" (symbol->string (c-coalesced-batch-id batch)))
        (define costs (c-coalesced-batch-candidate-costs batch))
        (when (eq? (hash-ref (c-coalesced-batch-selection-proof batch) 'mode) 'profile-guided)
          (unless (and (equal? (sort (hash-keys costs) symbol<?) (sort replay-strategy-order symbol<?))
                       (<= (hash-ref costs (c-coalesced-batch-strategy-id batch))
                           (apply min (hash-values costs))))
            (raise-syntax-error 'profile "selected replay strategy is not the profile cost minimum" (c-node-source root))))))
    selected)

  (define (expect-integer who x)
    (define v (syntax-e x))
    (unless (exact-integer? v)
      (raise-syntax-error who "expected an exact integer literal" x))
    v)

  ;; `state` 是声明式、固定大小的状态表。MVP 只接受整数，以便下面的
  ;; action 与 GPU glyph patch 可以完全在展开期确定。
  (define (parse-state-form stx)
    (syntax-parse stx
      #:datum-literals (state)
      [(state decl ...)
       (define states
         (for/list ([decl (in-list (syntax->list #'(decl ...)))])
           (syntax-parse decl
             [(name:id initial)
              (c-state (syntax-e #'name) (expect-integer 'state #'initial) decl)]
             [_ (raise-syntax-error 'state "expected [name integer-literal]" decl)])))
       (define ids (map c-state-id states))
       (unless (= (length ids) (set-count (list->set ids)))
         (raise-syntax-error 'state "duplicate state name" stx))
       states]
      [_ (raise-syntax-error 'state "expected (state [name integer-literal] ...)" stx)]))

  ;; action 支持 set 和受限的自增/自减。`(+ count 1)` 的状态 read、write
  ;; 与 delta 均在扩展期可知，因此能映射到确定的局部 GPU patch。
  (define (parse-action-form stx declared-state-ids)
    (syntax-parse stx
      #:datum-literals (action set +)
      [(action action-id:id (set target:id (+ source:id delta)))
       (define id (syntax-e #'action-id))
       (define target-id (syntax-e #'target))
       (define source-id (syntax-e #'source))
       (unless (set-member? declared-state-ids target-id)
         (raise-syntax-error 'action "writes an undeclared state" #'target))
       (unless (eq? target-id source-id)
         (raise-syntax-error 'action "MVP only supports (set x (+ x integer))" #'source))
       (c-action id target-id 'add (expect-integer 'action #'delta) stx)]
      [(action action-id:id (set target:id value))
       (define id (syntax-e #'action-id))
       (define target-id (syntax-e #'target))
       (unless (set-member? declared-state-ids target-id)
         (raise-syntax-error 'action "writes an undeclared state" #'target))
       (c-action id target-id 'set (expect-integer 'action #'value) stx)]
      [_ (raise-syntax-error 'action
                             "expected (action id (set state integer)) or (action id (set state (+ state integer)))"
                             stx)]))

  (define (parse-action-forms forms state-ids)
    (define actions (map (lambda (form) (parse-action-form form state-ids)) forms))
    (define ids (map c-action-id actions))
    (unless (= (length ids) (set-count (list->set ids)))
      (raise-syntax-error 'action "duplicate action id" (car forms)))
    actions)

  (define (parse-transaction-form stx declared-state-ids)
    ;; (commit-group apply-all sample-interval alert-threshold batch-size)
    ;; 成员是 syntax literals；没有 runtime schema、名称查找或动态集合。
    (syntax-parse stx
      #:datum-literals (commit-group)
      [(commit-group id:id state:id ...+)
       (define id-value (syntax-e #'id))
       (define state-values (map syntax-e (syntax->list #'(state ...))))
       (unless (= (length state-values) (length (remove-duplicates state-values)))
         (raise-syntax-error 'commit-group "member states must be unique" stx))
       (for ([state-id (in-list state-values)])
         (unless (set-member? declared-state-ids state-id)
           (raise-syntax-error 'commit-group (format "undeclared state ~a" state-id) stx)))
       (c-transaction id-value state-values)]
      [_ (raise-syntax-error 'commit-group "expected (commit-group id state ...+)" stx)]))

  (define (parse-transaction-forms forms state-ids)
    (if (null? forms)
        '()
        (let ([transactions (map (lambda (form) (parse-transaction-form form state-ids)) forms)])
          (define ids (map c-transaction-id transactions))
          (unless (= (length ids) (length (remove-duplicates ids)))
            (raise-syntax-error 'commit-group "duplicate transaction ID" (car forms)))
          transactions)))

  ;; `(command-table #:field command-entry (command "GPU" #:action refresh) ...)`
  ;; 是纯声明表：运行时没有 parser、字符串或 map lookup。
  (define (parse-command-table-form stx action-ids)
    (syntax-parse stx
      #:datum-literals (command-table command)
      [(command-table #:field field:id (command literal #:action action:id) ...+)
       (define field-id (syntax-e #'field))
       (for/list ([literal-stx (in-list (syntax->list #'(literal ...)))]
                  [action-stx (in-list (syntax->list #'(action ...)))])
         (define literal-value (syntax-e literal-stx))
         (define action-id (syntax-e action-stx))
         (unless (and (string? literal-value) (positive? (string-length literal-value)) (<= (string-length literal-value) 8)
                      (for/and ([ch (in-string literal-value)])
                        (or (char=? ch #\space) (and (char>=? ch #\A) (char<=? ch #\Z)))))
           (raise-syntax-error 'command-table "command literal must be 1..8 uppercase ASCII letters/spaces" literal-stx))
         (unless (set-member? action-ids action-id)
           (raise-syntax-error 'command-table "command action must name a declared action" action-stx))
         (c-command-spec field-id literal-value action-id))]
      [_ (raise-syntax-error 'command-table "expected (command-table #:field field (command \"WORD\" #:action action) ...)" stx)]))

  (define (parse-command-table-forms forms action-ids)
    (append-map (lambda (form) (parse-command-table-form form action-ids)) forms))

  ;; Navigation declarations are top-level compiler directives rather than layout nodes.
  ;; They contain no user expression: the compiler derives all transition operands from
  ;; the frozen list/scrollbar artifacts after layout and tile lowering.
  (define (parse-list-navigation-forms forms)
    (define specs
      (for/list ([form (in-list forms)])
        (syntax-parse form
          #:datum-literals (list-navigation)
          [(list-navigation #:id id:id #:for list-id:id #:scrollbar scrollbar-id:id)
           (c-list-navigation-spec (syntax-e #'id) (syntax-e #'list-id) (syntax-e #'scrollbar-id) form)]
          [_ (raise-syntax-error 'list-navigation
                                 "expected (list-navigation #:id id #:for virtual-list-id #:scrollbar scrollbar-id)"
                                 form)])))
    (define ids (map c-list-navigation-spec-id specs))
    (unless (= (length ids) (length (remove-duplicates ids)))
      (raise-syntax-error 'list-navigation "duplicate list-navigation ID" (car forms)))
    specs)

  (define (pack-uppercase-ascii literal)
    (for/fold ([packed 0]) ([ch (in-string literal)] [index (in-naturals)])
      (bitwise-ior packed (arithmetic-shift (char->integer ch) (* 8 index)))))

  (define (compile-command-matchers specs root focus-graph action-plans action-indexes)
    (define node-by-id (for/hash ([node (in-list (walk-nodes root))]) (values (c-node-id node) node)))
    (define focus-by-node (for/hash ([entry (in-list (c-focus-graph-entries focus-graph))]) (values (c-focus-entry-node-id entry) entry)))
    (define plan-by-id (for/hash ([plan (in-list action-plans)]) (values (c-action-plan-id plan) plan)))
    (define raw
      (for/list ([spec (in-list specs)])
        (let* ([field-id (c-command-spec-field spec)]
               [node (hash-ref node-by-id field-id
                               (lambda () (raise-syntax-error 'command-table "command field is not in layout" #f)))]
               [focus (hash-ref focus-by-node field-id
                                (lambda () (raise-syntax-error 'command-table "command table field must be focusable" (c-node-source node))))]
               [action (c-command-spec-action spec)]
               [plan (hash-ref plan-by-id action)]
               [literal (c-command-spec-literal spec)]
               [packed (pack-uppercase-ascii literal)])
          (unless (eq? (hash-ref (c-node-props node) 'charset #f) 'ascii-upper)
            (raise-syntax-error 'command-table "command table field must use #:charset ascii-upper" (c-node-source node)))
          (c-command-matcher field-id (c-focus-entry-slot focus) literal (string-length literal) packed
                             action (hash-ref action-indexes action)
                             (sort (remove-duplicates (append (c-focus-entry-tile-ids focus)
                                                              (c-action-plan-tile-ids plan))) <)))))
    (define keys
      (map (lambda (matcher)
             (list (c-command-matcher-field matcher)
                   (c-command-matcher-length matcher)
                   (c-command-matcher-packed matcher)))
           raw))
    (unless (= (length keys) (length (remove-duplicates keys)))
      (raise-syntax-error 'command-table "duplicate packed command literal for the same field" #f))
    (sort raw
          (lambda (left right)
            (or (symbol<? (c-command-matcher-field left) (c-command-matcher-field right))
                (and (eq? (c-command-matcher-field left) (c-command-matcher-field right))
                     (< (c-command-matcher-packed left) (c-command-matcher-packed right)))))))

  (define layout-props
(set '#:id '#:gap '#:padding '#:x '#:y '#:width '#:height '#:grow '#:align '#:justify
          '#:clip '#:background '#:radius '#:opacity '#:z '#:visual-flow '#:visual-anchor))
  (define leaf-props
(set '#:id '#:x '#:y '#:width '#:height '#:grow '#:align '#:clip '#:background
          '#:radius '#:opacity '#:max '#:z '#:font-scale '#:text-inset))

  (define (keyword-stx? x) (keyword? (syntax-e x)))

  (define (expect-number who x)
    (define v (syntax-e x))
    (unless (and (real? v) (>= v 0))
      (raise-syntax-error who "expected a non-negative numeric literal" x))
    v)

  (define (expect-positive-integer who x)
    (define v (syntax-e x))
    (unless (and (exact-integer? v) (> v 0))
      (raise-syntax-error who "expected a positive exact integer literal" x))
    v)

  (define (expect-nonnegative-integer who x)
    (define v (syntax-e x))
    (unless (exact-nonnegative-integer? v)
      (raise-syntax-error who "expected a non-negative exact integer literal" x))
    v)

  (define (expect-symbol who x)
    (define v (syntax-e x))
    (unless (symbol? v)
      (raise-syntax-error who "expected an identifier" x))
    v)

  ;; A theme exists only while `noir-app` expands its one static root.  Property
  ;; parsing resolves tokens here, so the runtime Scene cannot observe a theme map.
  (define current-static-theme (make-parameter #f))
  ;; A visual preset is an expansion-time canvas contract, not a runtime resize policy.
  ;; Existing fixture applications stay on bench; desktop examples opt into desktop-wide.
  (define visual-preset-table
    (hash 'bench (hash 'id 'bench 'width 640.0 'height 360.0 'margin 16.0)
          'desktop-compact (hash 'id 'desktop-compact 'width 1024.0 'height 720.0 'margin 24.0)
          'desktop-wide (hash 'id 'desktop-wide 'width 1280.0 'height 720.0 'margin 32.0)))
  (define current-static-visual-preset (make-parameter (hash-ref visual-preset-table 'bench)))
  (define (canvas-width) (hash-ref (current-static-visual-preset) 'width))
  (define (canvas-height) (hash-ref (current-static-visual-preset) 'height))
  (define (canvas-margin) (hash-ref (current-static-visual-preset) 'margin))
  (define (parse-visual-preset-form form)
    (syntax-parse form
      #:datum-literals (visual-preset)
      [(visual-preset preset:id)
       (define id (syntax-e #'preset))
       (hash-ref visual-preset-table id
                 (lambda ()
                   (raise-syntax-error 'visual-preset
                                       "expected bench, desktop-compact, or desktop-wide" #'preset)))]
      [_ (raise-syntax-error 'visual-preset "expected (visual-preset bench|desktop-compact|desktop-wide)" form)]))
;; The font-face index exists only during macro expansion. Runtime Scene data contains
;; already-resolved UV/advance/face evidence rather than a mutable font registry.
(define current-static-font-assets (make-parameter '()))
  (define current-static-dynamic-font-cell-asset (make-parameter #f))
  (define (with-static-font-assets assets thunk)
    (parameterize ([current-static-font-assets assets]) (thunk)))
  (define (with-static-dynamic-font-cell-asset asset thunk)
    (parameterize ([current-static-dynamic-font-cell-asset asset]) (thunk)))

  (define (parse-theme-hex who stx)
    (define text (syntax-e stx))
    (unless (and (string? text)
                 (regexp-match? #px"^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$" text))
      (raise-syntax-error who "theme colors must be #RRGGBB or #RRGGBBAA string literals" stx))
    (define (channel start)
      (/ (string->number (string-append "#x" (substring text start (+ start 2)))) 255.0))
    (list (channel 1) (channel 3) (channel 5)
          (if (= (string-length text) 9) (channel 7) 1.0)))

  (define (parse-theme-pairs who section value-parser)
    (define items (cdr (syntax->list section)))
    (unless (and items (even? (length items)))
      (raise-syntax-error who "theme section requires identifier/value pairs" section))
    (for/fold ([result (hash)]) ([index (in-range 0 (length items) 2)])
      (define name-stx (list-ref items index))
      (define value-stx (list-ref items (add1 index)))
      (define name (expect-symbol who name-stx))
      (when (hash-has-key? result name)
        (raise-syntax-error who (format "duplicate theme token ~a" name) name-stx))
      (hash-set result name (value-parser value-stx))))

  (define (parse-theme-form form)
    (define pieces (syntax->list form))
    (unless (and pieces (>= (length pieces) 3) (eq? (syntax-e (first pieces)) 'theme))
      (raise-syntax-error 'theme "expected (theme name (color ...) (space ...) (type ...) (radius ...) [(elevation ...)])" form))
    (define theme-id (expect-symbol 'theme (second pieces)))
    (define sections (drop pieces 2))
    (define parsed (make-hash))
    (for ([section (in-list sections)])
      (define section-items (syntax->list section))
      (unless (and section-items (pair? section-items))
        (raise-syntax-error 'theme "theme section must be a parenthesized literal section" section))
      (define kind (syntax-e (first section-items)))
      (when (hash-has-key? parsed kind)
        (raise-syntax-error 'theme (format "duplicate theme section ~a" kind) section))
      (define parser
        (case kind
          [(color) (lambda (value) (parse-theme-hex 'theme value))]
          [(space type radius)
           (lambda (value)
             (define number (syntax-e value))
             (unless (and (real? number) (> number 0))
               (raise-syntax-error 'theme "theme numeric values must be positive literals" value))
             number)]
          [(elevation)
           (lambda (value)
             (define number (syntax-e value))
             (unless (and (exact-integer? number) (<= 0 number 5))
               (raise-syntax-error 'theme "elevation tokens must be integer literals in [0, 5]" value))
             number)]
          [else (raise-syntax-error 'theme "theme sections are color, space, type, radius, or elevation" section)]))
      (hash-set! parsed kind (parse-theme-pairs 'theme section parser)))
    (for ([required '(color space type radius)])
      (unless (hash-has-key? parsed required)
        (raise-syntax-error 'theme (format "theme is missing required ~a section" required) form)))
    (hash 'id theme-id
          'color (hash-ref parsed 'color)
          'space (hash-ref parsed 'space)
          'type (hash-ref parsed 'type)
          'radius (hash-ref parsed 'radius)
          ;; Preserve backwards compatibility for existing themes while making elevation
          ;; a static, versionable semantic token for visual-language applications.
          'elevation (hash-ref parsed 'elevation (hash 'flat 0 'border 1 'raised 2 'overlay 3))))

  ;; Material Profile v1 is deliberately a compile-time-only baseline, not a
  ;; runtime theme API.  It exposes semantic M3-like tokens plus Noir aliases
  ;; required by the primitive desktop macros, all resolved before a Scene exists.
  (define material-profile-table
    (hash
     'material-dark
     (hash
      'id 'material-dark
      'color
      (hash
       ;; Material semantic roles.
       'primary '(0.8156862745 0.7372549020 1.0 1.0)
       'on-primary '(0.2196078431 0.1176470588 0.4470588235 1.0)
       'primary-container '(0.3098039216 0.2156862745 0.5450980392 1.0)
       'on-primary-container '(0.9176470588 0.8549019608 1.0 1.0)
       'secondary '(0.7960784314 0.7411764706 0.8666666667 1.0)
       'on-secondary '(0.1960784314 0.1647058824 0.2549019608 1.0)
       'secondary-container '(0.3098039216 0.2784313725 0.3843137255 1.0)
       'on-secondary-container '(0.9098039216 0.8313725490 1.0 1.0)
       'tertiary '(0.9372549020 0.7058823529 0.8470588235 1.0)
       'on-tertiary '(0.2862745098 0.1098039216 0.2470588235 1.0)
       'tertiary-container '(0.4862745098 0.3058823529 0.4431372549 1.0)
       'on-tertiary-container '(1.0 0.8470588235 0.9411764706 1.0)
       'error '(1.0 0.7058823529 0.7058823529 1.0)
       'on-error '(0.4117647059 0.0 0.0 1.0)
       'error-container '(0.5450980392 0.1019607843 0.1019607843 1.0)
       'on-error-container '(1.0 0.8549019608 0.8470588235 1.0)
       'background '(0.0784313725 0.0705882353 0.0941176471 1.0)
       'on-background '(0.9019607843 0.8784313725 0.9137254902 1.0)
       'surface '(0.0784313725 0.0705882353 0.0941176471 1.0)
       'surface-container-low '(0.1176470588 0.1098039216 0.1333333333 1.0)
       'surface-container '(0.1294117647 0.1215686275 0.1490196078 1.0)
       'surface-container-high '(0.1686274510 0.1607843137 0.1882352941 1.0)
       'surface-container-highest '(0.2117647059 0.2039215686 0.2313725490 1.0)
       'on-surface '(0.9019607843 0.8784313725 0.9137254902 1.0)
       'surface-variant '(0.2823529412 0.2666666667 0.3058823529 1.0)
       'on-surface-variant '(0.7921568627 0.7686274510 0.8156862745 1.0)
       'outline '(0.5725490196 0.5607843137 0.6000000000 1.0)
       'outline-variant '(0.2862745098 0.2666666667 0.3058823529 1.0)
       'inverse-surface '(0.9019607843 0.8784313725 0.9137254902 1.0)
       'inverse-on-surface '(0.1882352941 0.1803921569 0.2078431373 1.0)
       'inverse-primary '(0.4039215686 0.3215686275 0.6823529412 1.0)
       ;; Noir compatibility aliases; these retain a static semantic mapping.
       'canvas '(0.0784313725 0.0705882353 0.0941176471 1.0)
       'canvas-quiet '(0.0784313725 0.0705882353 0.0941176471 1.0)
       'rail '(0.1294117647 0.1215686275 0.1490196078 1.0)
       'surface-raised '(0.1686274510 0.1607843137 0.1882352941 1.0)
       'surface-hover '(0.2117647059 0.2039215686 0.2313725490 1.0)
       'surface-active '(0.3176470588 0.2980392157 0.3411764706 1.0)
       'surface-overlay '(0.1686274510 0.1607843137 0.1882352941 1.0)
       'border-subtle '(0.2862745098 0.2666666667 0.3058823529 1.0)
       'border-strong '(0.5725490196 0.5607843137 0.6000000000 1.0)
       'text-primary '(0.9019607843 0.8784313725 0.9137254902 1.0)
       'text-secondary '(0.7921568627 0.7686274510 0.8156862745 1.0)
       'text-muted '(0.5725490196 0.5607843137 0.6000000000 1.0)
       'text-inverse '(0.2196078431 0.1176470588 0.4470588235 1.0)
       'accent '(0.8156862745 0.7372549020 1.0 1.0)
       'accent-muted '(0.3098039216 0.2156862745 0.5450980392 1.0)
       'success '(0.4784313725 0.8392156863 0.6588235294 1.0)
       'warning '(1.0 0.7176470588 0.3019607843 1.0)
       'danger '(1.0 0.7058823529 0.7058823529 1.0)
       'info '(0.5843137255 0.7686274510 1.0 1.0)
       'panel '(0.1294117647 0.1215686275 0.1490196078 1.0)
       'header '(0.1294117647 0.1215686275 0.1490196078 1.0)
       'text '(0.9019607843 0.8784313725 0.9137254902 1.0)
       'muted '(0.5725490196 0.5607843137 0.6000000000 1.0))
      'space (hash 'hairline 1 'xxs 2 'xs 4 'sm 8 'md 12 'control 12 'card 16 'lg 24 'xl 32 'xxl 40 'page 32 'section 48)
      'type (hash 'meta 11 'caption 12 'body 14 'label 14 'control 14 'section 22 'title 28 'display 36)
      'radius (hash 'compact 4 'control 20 'field 4 'card 12 'panel 12 'overlay 28 'full 999)
      'elevation (hash 'flat 0 'border 1 'raised 1 'overlay 3 'level-0 0 'level-1 1 'level-2 2 'level-3 3 'level-4 4 'level-5 5))))

  (define (parse-material-profile-form form)
    (syntax-parse form
      #:datum-literals (material-profile)
      [(material-profile profile:id)
       (define id (syntax-e #'profile))
       (hash-ref material-profile-table id
                 (lambda ()
                   (raise-syntax-error 'material-profile
                                       "expected the frozen profile material-dark" #'profile)))]
      [_ (raise-syntax-error 'material-profile
                             "expected (material-profile material-dark)" form)]))

  (define (theme-token-value who kind x)
    (define call (syntax->list x))
    (define expected-head (case kind
                            [(color) 'theme-color]
                            [(space) 'theme-space]
                            [(type) 'theme-type]
                            [(radius) 'theme-radius]
                            [(elevation) 'theme-elevation]))
    (cond
      [(and call (= (length call) 2) (eq? (syntax-e (first call)) expected-head))
       (define theme (current-static-theme))
       (unless theme
         (raise-syntax-error who "theme token requires a (theme ...) declaration in the same noir-app" x))
       (define token (expect-symbol who (second call)))
       (hash-ref (hash-ref theme kind)
                 token
                 (lambda () (raise-syntax-error who (format "unknown ~a token ~a" kind token) (second call))))]
      [else #f]))

  (define (number-or-token who kind x)
    (or (theme-token-value who kind x) (expect-number who x)))

  (define (property-value who kw x)
    (case kw
      [(#:id) (expect-symbol who x)]
      [(#:gap #:padding) (number-or-token who 'space x)]
      [(#:radius) (number-or-token who 'radius x)]
      [(#:x #:y #:width #:height #:grow #:opacity #:z)
       (expect-number who x)]
      [(#:font-scale)
       (define value (syntax-e x))
       (unless (and (real? value) (<= 0.70 value 1.60))
         (raise-syntax-error who "#:font-scale must be a literal in [0.70, 1.60]" x))
       value]
      [(#:text-inset)
       (define value (syntax-e x))
       (unless (and (real? value) (<= 0.0 value 0.25))
         (raise-syntax-error who "#:text-inset must be a literal fraction in [0.0, 0.25]" x))
       value]
      [(#:clip)
       (define value (syntax-e x))
       (cond [(boolean? value) value]
             [(eq? value 'true) #t]
             [(eq? value 'false) #f]
             [else (raise-syntax-error who "#:clip expects true, false, #t, or #f" x)])]
      [(#:visual-flow #:visual-anchor)
       (define value (syntax-e x))
       (unless (boolean? value)
         (raise-syntax-error who "visual layout markers expect a boolean literal" x))
       value]
      [(#:charset)
       (define value (syntax-e x))
       (unless (memq value '(digits ascii-upper))
         (raise-syntax-error who "#:charset must be digits or ascii-upper" x))
       value]
      [(#:background) (or (theme-token-value who 'color x) (syntax-e x))]
      [(#:align #:justify)
       (define v (syntax-e x))
       (unless (memq v '(start center end stretch space-between))
         (raise-syntax-error who "expected start, center, end, stretch, or space-between" x))
       v]
      [(#:on) (expect-symbol who x)]
      [(#:multi-actions)
       (define forms (syntax->list x))
       (unless (and forms (pair? forms))
         (raise-syntax-error who "expected a non-empty literal action identifier list" x))
       (for/list ([form (in-list forms)]) (expect-symbol who form))]
      [(#:max-chars #:max) (expect-positive-integer who x)]
      [else (syntax-e x)]))

  ;; 消费连续 keyword/value 对；第一个非 keyword form 是 child 的开头。
  (define (parse-props who forms allowed)
    (let loop ([rest forms] [props (hash)])
      (cond
        [(null? rest) (values props '())]
        [(not (keyword-stx? (car rest))) (values props rest)]
        [(null? (cdr rest))
         (raise-syntax-error who "property keyword needs a value" (car rest))]
        [else
         (define kw (syntax-e (car rest)))
         (unless (set-member? allowed kw)
           (raise-syntax-error who (format "property ~a is not allowed here" kw) (car rest)))
          (when (hash-has-key? props kw)
            (raise-syntax-error who (format "duplicate property ~a" kw) (car rest)))
         (loop (cddr rest)
               (hash-set props kw (property-value who kw (cadr rest))))])))

  (define (default-id tag stx)
    (string->symbol (format "~a@~a" tag (or (syntax-position stx) 0))))

  (define (register-id tag stx props seen)
    (define id (hash-ref props '#:id (default-id tag stx)))
    (when (set-member? seen id)
      (raise-syntax-error 'ui (format "duplicate stable UI id: ~a" id) stx))
    (values id (hash-remove props '#:id) (set-add seen id)))

  (define (repeat-ui-form? stx)
    (define form (syntax->list stx))
    (and (pair? form) (eq? (syntax-e (car form)) 'repeat/ui)))

  ;; repeat/ui 是 layout child 的静态 splice，而不是 scene node。普通 child 返回长度 1 的列表；
  ;; repeat child 返回展开出的多个基础 node，二者随后经过同一 stable-ID registry。
  (define (parse-children forms seen)
    (let loop ([forms forms] [seen seen] [result '()])
      (cond
        [(null? forms) (values (reverse result) seen)]
        [else
         (define-values (nodes next-seen)
           (if (repeat-ui-form? (car forms))
               (parse-repeat-ui (car forms) seen)
               (let-values ([(node next-seen) (parse-node (car forms) seen)])
                 (values (list node) next-seen))))
         ;; result 以反序保存；foldl 保持 expanded child 的 surface order。
         (loop (cdr forms) next-seen
               (foldl (lambda (node acc) (cons node acc)) result nodes))])))

  (define (parse-layout tag stx forms seen)
    (define-values (props child-forms) (parse-props 'ui forms layout-props))
    (define-values (id clean-props seen*) (register-id tag stx props seen))
    (define-values (children seen**) (parse-children child-forms seen*))
    (values (c-node tag id clean-props children stx) seen**))

  (define (parse-text stx forms seen)
    ;; 文本允许属性与内容交错出现：
    ;; (text #:id title "static")
    ;; (text #:id fps #:dynamic frame-rate #:max-chars 3)
    (define allowed (set-add (set-add (set-add leaf-props '#:max-chars) '#:font-face) '#:charset))
    (let loop ([rest forms] [props (hash)] [static-value #f] [dynamic-value #f])
      (cond
        [(null? rest)
         (when (and static-value dynamic-value)
           (raise-syntax-error 'text "text cannot be both static and dynamic" stx))
         (unless (or static-value dynamic-value)
           (raise-syntax-error 'text "expected a string literal or #:dynamic identifier" stx))
         (when (and dynamic-value (not (hash-has-key? props '#:max-chars)))
           (raise-syntax-error 'text "dynamic text needs #:max-chars" stx))
          (when (and static-value (hash-has-key? props '#:max-chars))
            (raise-syntax-error 'text "#:max-chars is valid only for dynamic text" stx))
          (when (and static-value (hash-has-key? props '#:charset))
            (raise-syntax-error 'text "#:charset is valid only for dynamic text" stx))
          (when (and dynamic-value (hash-has-key? props '#:font-face))
            (raise-syntax-error 'text "#:font-face currently admits static text only; dynamic text stays on its frozen legacy atlas path" stx))
          (when (and dynamic-value (hash-has-key? props '#:font-scale))
            (raise-syntax-error 'text "#:font-scale is compile-time static fontc typography only" stx))
          (when (and static-value (hash-has-key? props '#:font-scale)
                     (not (hash-has-key? props '#:font-face)))
            (raise-syntax-error 'text "#:font-scale requires an explicit static #:font-face" stx))
          (when (and static-value (hash-has-key? props '#:font-face))
            (font-asset-by-face 'text (font-face-id 'text (hash-ref props '#:font-face) stx) stx))
         (define-values (id clean-props seen*) (register-id 'text stx props seen))
          (define final-props
            (if dynamic-value
                (hash-set
                 (hash-set
                  (hash-set
                   (hash-set (hash-remove (hash-remove clean-props '#:max-chars) '#:charset)
                             'value `(dynamic ,dynamic-value))
                   'max-chars (hash-ref props '#:max-chars))
                  'charset (hash-ref props '#:charset 'digits))
                 ;; 表面语法仍是 `text`，但动态节点的 IR lowering 明确是固定长度 text-run。
                 'lowering 'text-run)
               (hash-set
                (if (hash-has-key? clean-props '#:font-face)
                    (hash-set (hash-remove clean-props '#:font-face)
                              'font-face (font-face-id 'text (hash-ref props '#:font-face) stx))
                    clean-props)
                'value static-value)))
         (values (c-node 'text id final-props '() stx) seen*)]
        [(keyword-stx? (car rest))
         (define kw (syntax-e (car rest)))
         (when (null? (cdr rest))
           (raise-syntax-error 'text "property keyword needs a value" (car rest)))
         (cond
           [(eq? kw '#:dynamic)
            (when dynamic-value
              (raise-syntax-error 'text "duplicate #:dynamic" (car rest)))
            (loop (cddr rest) props static-value (expect-symbol 'text (cadr rest)))]
           [else
            (unless (set-member? allowed kw)
              (raise-syntax-error 'text (format "property ~a is not allowed here" kw) (car rest)))
            (when (hash-has-key? props kw)
              (raise-syntax-error 'text (format "duplicate property ~a" kw) (car rest)))
            (loop (cddr rest)
                  (hash-set props kw (property-value 'text kw (cadr rest)))
                  static-value dynamic-value)])]
        [else
         (define value (syntax-e (car rest)))
         (unless (string? value)
           (raise-syntax-error 'text "static text expects a string literal" (car rest)))
         (when static-value
           (raise-syntax-error 'text "text accepts exactly one string literal" (car rest)))
         (loop (cdr rest) props value dynamic-value)])))

  ;; text-field 在 macro expansion 内联为基础 stack/text/overlay 子树。field 本体保留调用者 ID；
  ;; placeholder、focus border 与 caret 使用稳定派生 ID，因此既有 layout/glyph/tile compiler 可直接复用。
  (define (parse-text-field stx seen)
    ;; (text-field #:id filter #:state filter-value #:max-chars 8 #:tab-index 0 [#:width n] [#:height n])
    (syntax-parse stx
      #:datum-literals (text-field)
      [(text-field #:id id:id #:state state:id #:max-chars max #:tab-index tab
                   (~optional (~seq #:charset charset:id) #:defaults ([charset #'digits]))
                   (~optional (~seq #:placeholder placeholder) #:defaults ([placeholder #'"INPUT"]))
                   (~optional (~seq #:on-enter enter:id) #:defaults ([enter #'#f]))
                   (~optional (~seq #:on-escape escape:id) #:defaults ([escape #'reset]))
                   (~optional (~seq #:width width) #:defaults ([width #'#f]))
                   (~optional (~seq #:height height) #:defaults ([height #'#f])))
       (define id-value (syntax-e #'id))
       (define state-value (syntax-e #'state))
       (define max-value (expect-positive-integer 'text-field #'max))
       (define tab-value (expect-nonnegative-integer 'text-field #'tab))
       (define charset-value (syntax-e #'charset))
       (define placeholder-value (component-literal-string 'text-field #'placeholder))
       (define enter-value (syntax-e #'enter))
       (define escape-value (syntax-e #'escape))
       (unless (eq? escape-value 'reset)
         (raise-syntax-error 'text-field "MVP Keyboard Command Map supports only #:on-escape reset" #'escape))
       (unless (memq charset-value '(digits ascii-upper))
         (raise-syntax-error 'text-field "Keyboard Map supports only #:charset digits or ascii-upper" #'charset))
       (when (and (eq? charset-value 'ascii-upper) (> max-value 8))
         (raise-syntax-error 'text-field "ascii-upper fixed text register supports at most 8 characters" #'max))
       (define extra-props
         (append (if (eq? (syntax-e #'width) #f) '()
                     (list '#:width (expect-number 'text-field #'width)))
                 (if (eq? (syntax-e #'height) #f) '()
                     (list '#:height (expect-number 'text-field #'height)))))
       (define shell-id (component-child-id id-value 'field-shell))
       (define focus-id (component-child-id id-value 'focus))
       (define placeholder-id (component-child-id id-value 'placeholder))
       (define caret-id (component-child-id id-value 'caret))
       ;; overlay alpha starts at zero. Runtime focus/blink only patch the alpha float in these fixed instances.
       (define lowered
         (datum->syntax stx
                        `(stack #:id ,shell-id ,@extra-props #:height 28 #:clip #t
                           (overlay #:id ,focus-id #:width ,(if (eq? (syntax-e #'width) #f) 0  (expect-number 'text-field #'width)) #:height 28 #:opacity 0.0 #:z 40)
                           (text #:id ,placeholder-id #:width ,(if (eq? (syntax-e #'width) #f) 0 (expect-number 'text-field #'width)) #:height 28 #:opacity 0.45 ,placeholder-value)
                           (text #:id ,id-value ,@extra-props #:dynamic ,state-value #:max-chars ,max-value)
                           (overlay #:id ,caret-id #:x 4 #:y 4 #:width 2 #:height 20 #:opacity 0.0 #:z 41))
                        stx stx))
       (define-values (shell seen*) (parse-node lowered seen))
       ;; locate original dynamic text child and annotate compiler-only focus/visual metadata.
       (define children (c-node-children shell))
       (define updated-children
         (for/list ([child (in-list children)])
           (if (eq? (c-node-id child) id-value)
               (struct-copy c-node child
                            [props (hash-set
                                    (hash-set
                                     (hash-set
                                      (hash-set
                                       (hash-set (c-node-props child) 'focusable #t)
                                       'tab-index tab-value)
                                      'charset charset-value)
                                     'visual-ids (list focus-id placeholder-id caret-id))
                                    'on-enter enter-value)])
               child)))
       (values (struct-copy c-node shell [children updated-children]) seen*)]
      [_ (raise-syntax-error 'text-field
                             "expected (text-field #:id id #:state state #:max-chars positive-int #:tab-index nonnegative-int [#:charset digits] [#:placeholder string] [#:on-enter action-id] [#:on-escape reset] [#:width n] [#:height n])"
                             stx)]))

  (define (parse-button stx forms seen)
    ;; (button #:id refresh "Refresh" #:on refresh-data)
    (define allowed (set-add (set-add (set-add leaf-props '#:on) '#:transaction-op) '#:multi-actions))
    (let loop ([rest forms] [props (hash)] [label #f])
      (cond
        [(null? rest)
         (unless label
           (raise-syntax-error 'button "button needs one static string label" stx))
         (unless (hash-has-key? props '#:on)
           (raise-syntax-error 'button "button needs #:on action-id" stx))
         (define-values (id clean-props seen*) (register-id 'button stx props seen))
         (values (c-node 'button id
                         (hash-set (hash-set (hash-remove clean-props '#:on) 'label label)
                                   'on (hash-ref props '#:on))
                         '() stx)
                 seen*)]
        [(keyword-stx? (car rest))
         (when (null? (cdr rest))
           (raise-syntax-error 'button "property keyword needs a value" (car rest)))
         (define kw (syntax-e (car rest)))
         (unless (set-member? allowed kw)
           (raise-syntax-error 'button (format "property ~a is not allowed here" kw) (car rest)))
         (when (hash-has-key? props kw)
           (raise-syntax-error 'button (format "duplicate property ~a" kw) (car rest)))
         (loop (cddr rest)
               (hash-set props kw (property-value 'button kw (cadr rest)))
               label)]
        [else
         (define value (syntax-e (car rest)))
         (unless (string? value)
           (raise-syntax-error 'button "button label must be a string literal" (car rest)))
         (when label
           (raise-syntax-error 'button "button accepts exactly one label" (car rest)))
         (loop (cdr rest) props value)])))

  (define (parse-transaction-button stx seen)
    ;; (transaction-button #:id apply-all #:transaction apply-all #:operation commit "Apply All")
    ;; 降低后仍是普通 button；transaction metadata 只由 compile-event-map 消费。
    (syntax-parse stx
      #:datum-literals (transaction-button)
      [(transaction-button #:id id:id #:transaction transaction:id #:operation operation:id
                           (~optional (~seq #:width width) #:defaults ([width #'#f]))
                           (~optional (~seq #:height height) #:defaults ([height #'#f])) label)
       (define op (syntax-e #'operation))
       (unless (memq op '(commit reset))
         (raise-syntax-error 'transaction-button "#:operation must be commit or reset" #'operation))
       (define label-value (component-literal-string 'transaction-button #'label))
       (define lowered
         (datum->syntax stx
                        `(button #:id ,(syntax-e #'id) #:on ,(syntax-e #'transaction)
                                 #:transaction-op ,op
                                 ,@(if (eq? (syntax-e #'width) #f) '() (list '#:width (expect-positive-integer 'transaction-button #'width)))
                                 ,@(if (eq? (syntax-e #'height) #f) '() (list '#:height (expect-positive-integer 'transaction-button #'height)))
                                 ,label-value)
                        stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'transaction-button
                             "expected (transaction-button #:id id #:transaction transaction-id #:operation commit-or-reset [#:width positive-int] [#:height positive-int] string)"
                             stx)]))

  ;; multi-action-event is a static event fixture primitive.  It lowers to a
  ;; base button with a literal action list; frame scheduling consumes the list
  ;; at macro expansion and emits no runtime callback aggregation.
  (define (parse-multi-action-event stx seen)
    ;; (multi-action-event #:id refresh-all #:actions (refresh-a refresh-b) "Refresh")
    (syntax-parse stx
      #:datum-literals (multi-action-event)
      [(multi-action-event #:id id:id #:actions (action:id ...+)
                           (~optional (~seq #:width width) #:defaults ([width #'#f]))
                           (~optional (~seq #:height height) #:defaults ([height #'#f])) label)
       (define label-value (component-literal-string 'multi-action-event #'label))
       (define actions (map syntax-e (syntax->list #'(action ...))))
       (define lowered
         (datum->syntax stx
                        `(button #:id ,(syntax-e #'id) #:on ,(car actions)
                                 #:multi-actions ,actions
                                 ,@(if (eq? (syntax-e #'width) #f) '()
                                       (list '#:width (expect-positive-integer 'multi-action-event #'width)))
                                 ,@(if (eq? (syntax-e #'height) #f) '()
                                       (list '#:height (expect-positive-integer 'multi-action-event #'height)))
                                 ,label-value)
                        stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'multi-action-event
                             "expected (multi-action-event #:id id #:actions (action-id ...+) [#:width positive-int] [#:height positive-int] string)"
                             stx)]))

  ;; multi-field-event is a static event fixture primitive. Its transaction ID is
  ;; a literal compiler key; the transaction plan later fixes all member slots.
  (define (parse-multi-field-event stx seen)
    ;; (multi-field-event #:id commit-three #:transaction apply-all #:operation commit "Commit three")
    (syntax-parse stx
      #:datum-literals (multi-field-event)
      [(multi-field-event #:id id:id #:transaction transaction:id #:operation operation:id
                          (~optional (~seq #:width width) #:defaults ([width #'#f]))
                          (~optional (~seq #:height height) #:defaults ([height #'#f])) label)
       (define op (syntax-e #'operation))
       (unless (memq op '(commit reset))
         (raise-syntax-error 'multi-field-event "#:operation must be commit or reset" #'operation))
       (define label-value (component-literal-string 'multi-field-event #'label))
       (define lowered
         (datum->syntax stx
                        `(transaction-button #:id ,(syntax-e #'id)
                                             #:transaction ,(syntax-e #'transaction)
                                             #:operation ,op
                                             ,@(if (eq? (syntax-e #'width) #f) '()
                                                   (list '#:width (expect-positive-integer 'multi-field-event #'width)))
                                             ,@(if (eq? (syntax-e #'height) #f) '()
                                                   (list '#:height (expect-positive-integer 'multi-field-event #'height)))
                                             ,label-value)
                        stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'multi-field-event
                             "expected (multi-field-event #:id id #:transaction transaction-id #:operation commit-or-reset [#:width positive-int] [#:height positive-int] string)"
                             stx)]))

  ;; 组件宏不在 runtime 保留对象，也不引入第二套 layout/event lowering。它们把受限的
  ;; 静态参数映射为基础语法，再递归进入 `parse-node`；由 outer id 派生的 child id
  ;; 是稳定、可审计且避免与调用者显式 id 冲突的 compiler 内联命名空间。
  (define (component-child-id id suffix)
    (string->symbol (format "~a$~a" id suffix)))
  (define (component-literal-string who stx)
    (define value (syntax-e stx))
    (unless (string? value)
      (raise-syntax-error who "expected a static string literal" stx))
    value)
  ;; form-row 和 settings-form 是表单语法糖，不引入 runtime widget/trait/virtual tree。
  ;; form-row 保留 row 的调用者 ID；它的三个子节点使用稳定 namespace：label、field、apply。
  (define (parse-form-row stx seen)
    ;; (form-row #:id sample-rate #:label "Sampling interval" #:state sample-value
    ;;           #:max-chars 3 #:tab-index 0 #:on-enter commit #:on-apply apply-sample
    ;;           [#:placeholder "001"] [#:label-width 176] [#:field-width 180]
    ;;           [#:button-width 88] [#:gap 12] [#:apply-label "Apply"])
    ;; `#:on-apply` 省略时保持与旧 API 相同：button action = #:on-enter。
    ;; => (row #:id sample-rate #:height 46 #:gap 12
    ;;      (text #:id sample-rate$label #:width 176 "Sampling interval")
    ;;      (text-field #:id sample-rate$field ... #:on-enter commit #:width 180)
    ;;      (button #:id sample-rate$apply #:width 88 "Apply" #:on apply-sample))
    (syntax-parse stx
      #:datum-literals (form-row)
      [(form-row #:id id:id #:label label #:state state:id #:max-chars max #:tab-index tab #:on-enter action:id
                 (~optional (~seq #:on-apply apply:id) #:defaults ([apply #'#f]))
                 (~optional (~seq #:placeholder placeholder) #:defaults ([placeholder #'"VALUE"]))
                 (~optional (~seq #:label-width label-width) #:defaults ([label-width #'176]))
                 (~optional (~seq #:field-width field-width) #:defaults ([field-width #'180]))
                 (~optional (~seq #:button-width button-width) #:defaults ([button-width #'88]))
                 (~optional (~seq #:gap gap) #:defaults ([gap #'12]))
                 (~optional (~seq #:apply-label apply-label) #:defaults ([apply-label #'"Apply"])))
       (define id-value (syntax-e #'id))
       (define state-value (syntax-e #'state))
       (define enter-value (syntax-e #'action))
       (define action-value (if (eq? (syntax-e #'apply) #f) enter-value (syntax-e #'apply)))
       (define label-value (component-literal-string 'form-row #'label))
       (define placeholder-value (component-literal-string 'form-row #'placeholder))
       (define apply-label-value (component-literal-string 'form-row #'apply-label))
       (define max-value (expect-positive-integer 'form-row #'max))
       (define tab-value (expect-nonnegative-integer 'form-row #'tab))
       (define label-width-value (expect-positive-integer 'form-row #'label-width))
       (define field-width-value (expect-positive-integer 'form-row #'field-width))
       (define button-width-value (expect-positive-integer 'form-row #'button-width))
       (define gap-value (expect-number 'form-row #'gap))
       (define label-id (component-child-id id-value 'label))
       (define field-id (component-child-id id-value 'field))
       (define apply-id (component-child-id id-value 'apply))
       (define lowered
         (datum->syntax stx
                        `(row #:id ,id-value #:height 46 #:gap ,gap-value
                           (text #:id ,label-id #:width ,label-width-value ,label-value)
                           (text-field #:id ,field-id #:state ,state-value #:max-chars ,max-value #:tab-index ,tab-value
                                       #:placeholder ,placeholder-value #:on-enter ,enter-value #:on-escape reset #:width ,field-width-value)
                           (button #:id ,apply-id #:width ,button-width-value ,apply-label-value #:on ,action-value))
                        stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'form-row
                             "expected (form-row #:id id #:label string #:state state #:max-chars positive-int #:tab-index nonnegative-int #:on-enter commit-or-action [#:on-apply action] [#:placeholder string] [#:label-width positive-int] [#:field-width positive-int] [#:button-width positive-int] [#:gap n] [#:apply-label string])"
                             stx)]))

  (define (form-row-form? stx)
    (define form (syntax->list stx))
    (and (pair? form) (eq? (syntax-e (car form)) 'form-row)))

  (define (parse-settings-form stx seen)
    ;; settings-form 仅接收静态 form-row 列表；它自身降低成普通 column。
    ;; 因而没有 form schema、row registry、runtime iterator 或 generic command dispatcher。
    (syntax-parse stx
      #:datum-literals (settings-form)
      [(settings-form #:id id:id
                      (~optional (~seq #:gap gap) #:defaults ([gap #'12]))
                      (~optional (~seq #:padding padding) #:defaults ([padding #'16]))
                      (~optional (~seq #:background background:id) #:defaults ([background #'dark]))
                      child ...+)
       (define id-value (syntax-e #'id))
       (define gap-value (expect-number 'settings-form #'gap))
       (define padding-value (expect-number 'settings-form #'padding))
       (define background-value (syntax-e #'background))
       (define child-forms (syntax->list #'(child ...)))
       (unless (andmap form-row-form? child-forms)
         (raise-syntax-error 'settings-form "accepts only literal form-row children" stx))
       (define lowered
         (datum->syntax stx
                        `(column #:id ,id-value #:gap ,gap-value #:padding ,padding-value #:background ,background-value
                           ,@(map syntax->datum child-forms))
                        stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'settings-form
                             "expected (settings-form #:id id [#:gap n] [#:padding n] [#:background color] form-row ...+)"
                             stx)]))

  (define (parse-metric-card stx seen)
    ;; (metric-card #:id fps-card #:label "FPS" #:dynamic frame-rate #:max-chars 3
    ;;              [#:gap 6] [#:padding 8])
    ;; => (column ... (text ... label) (text ... #:dynamic state #:max-chars n))
    (syntax-parse stx
      #:datum-literals (metric-card)
      [(metric-card #:id id:id #:label label #:dynamic state:id #:max-chars max
                    (~optional (~seq #:gap gap) #:defaults ([gap #'6]))
                    (~optional (~seq #:padding padding) #:defaults ([padding #'8])))
       (define id-value (syntax-e #'id))
       (define label-value (component-literal-string 'metric-card #'label))
       (define max-value (expect-positive-integer 'metric-card #'max))
       (define gap-value (expect-number 'metric-card #'gap))
       (define padding-value (expect-number 'metric-card #'padding))
       (define label-id (component-child-id id-value 'label))
       (define value-id (component-child-id id-value 'value))
       (define lowered
         (datum->syntax stx
                        `(column #:id ,id-value #:gap ,gap-value #:padding ,padding-value
                           (text #:id ,label-id ,label-value)
                           (text #:id ,value-id #:dynamic ,(syntax-e #'state) #:max-chars ,max-value))
                        stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'metric-card
                             "expected (metric-card #:id id #:label string #:dynamic state #:max-chars positive-int [#:gap n] [#:padding n])"
                             stx)]))
  (define (parse-control-button stx seen)
    ;; (control-button #:id refresh #:label "Refresh" #:on refresh-data
    ;;                 [#:width n] [#:height n] [#:grow n])
    ;; => (button #:id refresh "Refresh" #:on refresh-data ...)
    (syntax-parse stx
      #:datum-literals (control-button)
      [(control-button #:id id:id #:label label #:on action:id
                       (~optional (~seq #:width width) #:defaults ([width #'#f]))
                       (~optional (~seq #:height height) #:defaults ([height #'#f]))
                       (~optional (~seq #:grow grow) #:defaults ([grow #'#f])))
       (define id-value (syntax-e #'id))
       (define label-value (component-literal-string 'control-button #'label))
       (define action-value (syntax-e #'action))
       (define optional-props
         (append (if (eq? (syntax-e #'width) #f) '()
                     (list '#:width (expect-number 'control-button #'width)))
                 (if (eq? (syntax-e #'height) #f) '()
                     (list '#:height (expect-number 'control-button #'height)))
                 (if (eq? (syntax-e #'grow) #f) '()
                     (list '#:grow (expect-number 'control-button #'grow)))))
       (define lowered
         (datum->syntax stx
                        `(button #:id ,id-value ,@optional-props ,label-value #:on ,action-value)
                        stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'control-button
                             "expected (control-button #:id id #:label string #:on action [#:width n] [#:height n] [#:grow n])"
                             stx)]))

  ;; Desktop chrome v1 is syntax compression only. These parsers lower directly
  ;; into the existing primitive grammar; no c-node ever carries a component tag.
  (define (parse-app-shell stx seen)
    (syntax-parse stx
      #:datum-literals (app-shell)
      [(app-shell #:id id:id
                  (~optional (~seq #:gap gap) #:defaults ([gap #'(theme-space sm)]))
                  (~optional (~seq #:padding padding) #:defaults ([padding #'(theme-space lg)]))
                  (~optional (~seq #:background background) #:defaults ([background #'(theme-color canvas)]))
                  (~optional (~seq #:radius radius) #:defaults ([radius #'(theme-radius panel)]))
                  child:expr ...+)
       (define id-value (syntax-e #'id))
       (define frame-height (- (canvas-height) (* 2.0 (canvas-margin))))
       (define content-id (component-child-id id-value 'content))
       (define lowered
         (datum->syntax stx
                        `(stack #:id ,id-value #:height ,frame-height #:clip #t
                                #:background ,(syntax->datum #'background)
                           (column #:id ,content-id #:visual-flow #t
                                    #:gap ,(syntax->datum #'gap)
                                    #:padding ,(syntax->datum #'padding)
                                    ,@(map syntax->datum (syntax->list #'(child ...)))))
                        stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'app-shell
                             "expected (app-shell #:id id [#:gap n] [#:padding n] [#:background color] [#:radius n] child ...+)"
                             stx)]))

  (define (parse-surface stx seen)
    (syntax-parse stx
      #:datum-literals (surface)
      [(surface #:id id:id
                (~optional (~seq #:x x) #:defaults ([x #'#f]))
                (~optional (~seq #:y y) #:defaults ([y #'#f]))
                (~optional (~seq #:width width) #:defaults ([width #'#f]))
                (~optional (~seq #:height height) #:defaults ([height #'#f]))
                (~optional (~seq #:background background) #:defaults ([background #'(theme-color surface)]))
                (~optional (~seq #:elevation elevation) #:defaults ([elevation #'(theme-elevation flat)]))
                (~optional (~seq #:radius radius) #:defaults ([radius #'#f]))
                (~optional (~seq #:clip clip) #:defaults ([clip #'#f]))
                child:expr ...+)
       (define id-value (syntax-e #'id))
       (define x-value (and (not (eq? (syntax-e #'x) #f)) (expect-number 'surface #'x)))
       (define y-value (and (not (eq? (syntax-e #'y) #f)) (expect-number 'surface #'y)))
       (define width-value (and (not (eq? (syntax-e #'width) #f)) (expect-number 'surface #'width)))
       (define height-value (and (not (eq? (syntax-e #'height) #f)) (expect-number 'surface #'height)))
       (define elevation-value
         (or (theme-token-value 'surface 'elevation #'elevation)
             (let ([value (syntax-e #'elevation)])
               (unless (and (exact-integer? value) (<= 0 value 5))
                 (raise-syntax-error 'surface "#:elevation expects 0..5 or (theme-elevation token)" #'elevation))
               value)))
       (when (and (> elevation-value 0) (not height-value))
         (raise-syntax-error 'surface "border/raised/overlay surface needs a fixed #:height" stx))
       (define optional-props
         (append (if x-value (list '#:x x-value) '())
                 (if y-value (list '#:y y-value) '())
                 (if width-value (list '#:width width-value) '())
                 (if height-value (list '#:height height-value) '())
                 (if (eq? (syntax-e #'radius) #f) '() (list '#:radius (syntax->datum #'radius)))))
       ;; Elevation is a finite compile-time overlay recipe. No blur, query or dynamic shadow exists.
       (define decorations
         (if (> elevation-value 0)
             (list `(overlay #:id ,(component-child-id id-value 'border-bottom)
                             #:y ,(- height-value 1) #:height 1
                             #:background (theme-color border-subtle) #:opacity 1.0 #:z 8))
             '()))
       (define lowered
         (datum->syntax stx
                        `(stack #:id ,id-value ,@optional-props
                                #:visual-anchor #t
                                #:clip ,(syntax->datum #'clip)
                                #:background ,(syntax->datum #'background)
                                ,@decorations
                                ,@(map syntax->datum (syntax->list #'(child ...))))
                        stx stx))
       (define-values (surface-node surface-seen) (parse-node lowered seen))
       ;; `elevation` is retained only in compiler IR. It is never a runtime style
       ;; lookup: shadow lowering consumes this literal after layout is frozen.
       (values (struct-copy c-node surface-node
                            [props (hash-set (c-node-props surface-node) 'elevation elevation-value)])
               surface-seen)]
       [_ (raise-syntax-error 'surface
                             "expected (surface #:id id [#:x n] [#:y n] [#:width n] [#:height n] [#:background color] [#:elevation 0..5] [#:radius n] [#:clip bool] child ...+)"
                             stx)]))

  (define (parse-divider stx seen)
    (syntax-parse stx
      #:datum-literals (divider)
      [(divider #:id id:id
                (~optional (~seq #:height height) #:defaults ([height #'1]))
                (~optional (~seq #:background background) #:defaults ([background #'(theme-color border-subtle)])))
       (define height-value (expect-positive-integer 'divider #'height))
       (define lowered
         (datum->syntax stx
                        `(overlay #:id ,(syntax-e #'id) #:height ,height-value
                                  #:background ,(syntax->datum #'background) #:opacity 1.0 #:z 8)
                        stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'divider "expected (divider #:id id [#:height positive-int] [#:background color])" stx)]))

  (define (parse-status-indicator stx seen)
    (syntax-parse stx
      #:datum-literals (status-indicator)
      [(status-indicator #:id id:id #:height height #:background background
                         (~optional (~seq #:width width) #:defaults ([width #'4])))
       (define width-value (expect-positive-integer 'status-indicator #'width))
       (define height-value (expect-positive-integer 'status-indicator #'height))
       (define lowered
         (datum->syntax stx
                        `(overlay #:id ,(syntax-e #'id) #:width ,width-value #:height ,height-value
                                  #:background ,(syntax->datum #'background) #:opacity 1.0 #:z 12)
                        stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'status-indicator
                             "expected (status-indicator #:id id #:height positive-int #:background color [#:width positive-int])" stx)]))

  (define (parse-toolbar stx seen)
    (syntax-parse stx
      #:datum-literals (toolbar)
      [(toolbar #:id id:id #:text-id text-id:id #:label label #:font-face face:id
                (~optional (~seq #:height height) #:defaults ([height #'34]))
                (~optional (~seq #:background background) #:defaults ([background #'(theme-color surface-raised)])))
       (define id-value (syntax-e #'id))
       (define height-value (expect-positive-integer 'toolbar #'height))
       (define label-value (component-literal-string 'toolbar #'label))
       (define lowered
         (datum->syntax stx
                        `(stack #:id ,id-value #:height ,height-value
                                #:background ,(syntax->datum #'background)
                           (text #:id ,(syntax-e #'text-id) #:height ,height-value
                                 #:background ,(syntax->datum #'background)
                                 #:font-face ,(syntax-e #'face) ,label-value)
                           (overlay #:id ,(component-child-id id-value 'divider)
                                    #:y ,(- height-value 1) #:height 1
                                    #:background (theme-color border-strong) #:opacity 1.0 #:z 10))
                        stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'toolbar
                             "expected (toolbar #:id id #:text-id id #:label string #:font-face face [#:height n] [#:background color])"
                             stx)]))

  (define (parse-table-header stx seen)
    (syntax-parse stx
      #:datum-literals (table-header)
      [(table-header #:id id:id #:text-id text-id:id #:label label #:font-face face:id
                     (~optional (~seq #:height height) #:defaults ([height #'24]))
                     (~optional (~seq #:background background) #:defaults ([background #'(theme-color surface)])))
       (define id-value (syntax-e #'id))
       (define height-value (expect-positive-integer 'table-header #'height))
       (define label-value (component-literal-string 'table-header #'label))
       (define lowered
         (datum->syntax stx
                        `(stack #:id ,id-value #:height ,height-value
                                #:background ,(syntax->datum #'background)
                           (text #:id ,(syntax-e #'text-id) #:height ,height-value
                                 #:background ,(syntax->datum #'background)
                                 #:font-face ,(syntax-e #'face) ,label-value)
                           (overlay #:id ,(component-child-id id-value 'divider)
                                    #:y ,(- height-value 1) #:height 1
                                    #:background (theme-color border-subtle) #:opacity 1.0 #:z 10))
                        stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'table-header
                             "expected (table-header #:id id #:text-id id #:label string #:font-face face [#:height n] [#:background color])"
                             stx)]))

  (define (parse-status-pill stx seen)
    (syntax-parse stx
      #:datum-literals (status-pill)
      [(status-pill #:id id:id #:button-id button-id:id #:label-id label-id:id
                    #:button-label button-label #:label label #:font-face face:id #:on action:id
                    (~optional (~seq #:height height) #:defaults ([height #'30]))
                    #:background background)
       (define button-label-value (component-literal-string 'status-pill #'button-label))
       (define label-value (component-literal-string 'status-pill #'label))
       (define lowered
         (datum->syntax stx
                        `(stack #:id ,(syntax-e #'id) #:height ,(syntax->datum #'height)
                                #:background ,(syntax->datum #'background)
                           (button #:id ,(syntax-e #'button-id) #:height ,(syntax->datum #'height)
                                   #:radius (theme-radius card) #:background ,(syntax->datum #'background)
                                   ,button-label-value #:on ,(syntax-e #'action))
                           (text #:id ,(syntax-e #'label-id) #:height ,(syntax->datum #'height)
                                 #:background ,(syntax->datum #'background)
                                 #:font-face ,(syntax-e #'face) ,label-value))
                        stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'status-pill
                             "expected (status-pill #:id id #:button-id id #:label-id id #:button-label string #:label string #:font-face face #:on action [#:height n] #:background color)"
                             stx)]))

  (define (parse-detail-panel stx seen)
    (syntax-parse stx
      #:datum-literals (detail-panel)
      [(detail-panel #:id id:id #:text-id text-id:id #:dynamic state:id #:max-chars max
                     (~optional (~seq #:x x) #:defaults ([x #'0]))
                     (~optional (~seq #:y y) #:defaults ([y #'0]))
                     (~optional (~seq #:width width) #:defaults ([width #'#f]))
                     (~optional (~seq #:height height) #:defaults ([height #'34]))
                     (~optional (~seq #:background background) #:defaults ([background #'(theme-color surface-raised)])))
       (define id-value (syntax-e #'id))
       (define max-value (expect-positive-integer 'detail-panel #'max))
       (define x-value (expect-number 'detail-panel #'x))
       (define y-value (expect-number 'detail-panel #'y))
       (define width-value (and (not (eq? (syntax-e #'width) #f)) (expect-positive-integer 'detail-panel #'width)))
       (define height-value (expect-positive-integer 'detail-panel #'height))
       (define lowered
         (datum->syntax stx
                        `(stack #:id ,id-value #:x ,x-value #:y ,y-value
                                ,@(if width-value (list '#:width width-value) '())
                                #:height ,height-value #:visual-anchor #t #:radius (theme-radius card)
                                #:background ,(syntax->datum #'background)
                           (text #:id ,(syntax-e #'text-id) #:height ,height-value
                                 #:background ,(syntax->datum #'background)
                                 #:dynamic ,(syntax-e #'state) #:max-chars ,max-value #:charset ascii-upper)
                           (overlay #:id ,(component-child-id id-value 'divider)
                                    #:height 1 #:background (theme-color border-subtle) #:opacity 1.0 #:z 10))
                        stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'detail-panel
                             "expected (detail-panel #:id id #:text-id id #:dynamic state #:max-chars positive-int [#:x n] [#:y n] [#:width n] [#:height n] [#:background color])"
                             stx)]))

  ;; Visual Language v2 components remain syntax-only. Every child coordinate is
  ;; resolved during expansion against the fixed desktop-wide canvas; none of these
  ;; tags survives in c-node or the runtime Scene.
  (define (parse-workspace-shell stx seen)
    (syntax-parse stx
      #:datum-literals (workspace-shell)
      [(workspace-shell #:id id:id #:rail-id rail-id:id #:brand-id brand-id:id #:meta-id meta-id:id
                        #:brand brand #:meta meta #:font-face face:id
                        (~optional (~seq #:rail-width rail-width) #:defaults ([rail-width #'168]))
                        (~optional (~seq #:workspace-x workspace-x) #:defaults ([workspace-x #'188]))
                        (~optional (~seq #:background background) #:defaults ([background #'(theme-color canvas)]))
                        (~optional (~seq #:rail-background rail-background) #:defaults ([rail-background #'(theme-color rail)]))
                        child:expr ...+)
       (define id-value (syntax-e #'id))
       (define rail-width-value (expect-positive-integer 'workspace-shell #'rail-width))
       (define workspace-x-value (expect-positive-integer 'workspace-shell #'workspace-x))
       (define frame-height (- (canvas-height) (* 2.0 (canvas-margin))))
       (define frame-width (- (canvas-width) (* 2.0 (canvas-margin))))
       (define workspace-width (- frame-width workspace-x-value))
       (define brand-value (component-literal-string 'workspace-shell #'brand))
       (define meta-value (component-literal-string 'workspace-shell #'meta))
       (define lowered
         (datum->syntax
          stx
          `(stack #:id ,id-value #:width ,frame-width #:height ,frame-height #:clip #t
                  #:background ,(syntax->datum #'background)
             (overlay #:id ,(syntax-e #'rail-id) #:width ,rail-width-value #:height ,frame-height
                      #:background ,(syntax->datum #'rail-background) #:opacity 1.0 #:z 1)
             (overlay #:id ,(component-child-id id-value 'rail-accent) #:width 4 #:height 72
                      #:background (theme-color accent) #:opacity 1.0 #:z 3)
             (text #:id ,(syntax-e #'brand-id) #:x 20 #:y 22 #:width ,(- rail-width-value 36) #:height 42
                   #:font-face ,(syntax-e #'face) #:font-scale 0.85 #:text-inset 0.0 ,brand-value)
             (text #:id ,(syntax-e #'meta-id) #:x 20 #:y 76 #:width ,(- rail-width-value 36) #:height 24
                   #:font-face ,(syntax-e #'face) #:font-scale 0.72 #:text-inset 0.0 ,meta-value)
             (overlay #:id ,(component-child-id id-value 'workspace) #:x ,workspace-x-value
                      #:width ,workspace-width #:height ,frame-height
                      #:background (theme-color canvas-quiet) #:opacity 1.0 #:z 0)
             ,@(map syntax->datum (syntax->list #'(child ...))))
          stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'workspace-shell
                             "expected stable IDs, static brand/meta strings, a font face, and fixed children"
                             stx)]))

  (define (parse-page-header stx seen)
    (syntax-parse stx
      #:datum-literals (page-header)
      [(page-header #:id id:id #:eyebrow-id eyebrow-id:id #:title-id title-id:id #:meta-id meta-id:id
                    #:eyebrow eyebrow #:title title #:meta meta #:font-face face:id
                    #:x x #:y y #:width width
                    (~optional (~seq #:height height) #:defaults ([height #'76]))
                    (~optional (~seq #:background background) #:defaults ([background #'(theme-color surface-raised)])))
       (define id-value (syntax-e #'id))
       (define x-value (expect-number 'page-header #'x))
       (define y-value (expect-number 'page-header #'y))
       (define width-value (expect-positive-integer 'page-header #'width))
       (define height-value (expect-positive-integer 'page-header #'height))
       (define eyebrow-value (component-literal-string 'page-header #'eyebrow))
       (define title-value (component-literal-string 'page-header #'title))
       (define meta-value (component-literal-string 'page-header #'meta))
       (define lowered
         (datum->syntax
          stx
          `(stack #:id ,id-value #:x ,x-value #:y ,y-value #:width ,width-value #:height ,height-value
                  #:radius (theme-radius card) #:background ,(syntax->datum #'background)
             (text #:id ,(syntax-e #'eyebrow-id) #:x ,(+ x-value 24) #:y ,(+ y-value 6)
                   #:width ,(- width-value 48) #:height 18 #:font-face ,(syntax-e #'face)
                   #:font-scale 0.72 #:text-inset 0.0 ,eyebrow-value)
             (text #:id ,(syntax-e #'title-id) #:x ,(+ x-value 24) #:y ,(+ y-value 22)
                   #:width ,(- width-value 48) #:height 44 #:font-face ,(syntax-e #'face)
                   #:font-scale 1.00 #:text-inset 0.0 ,title-value)
             (text #:id ,(syntax-e #'meta-id) #:x ,(+ x-value 632) #:y ,(+ y-value 23)
                   #:width ,(- width-value 656) #:height 28 #:font-face ,(syntax-e #'face)
                   #:font-scale 0.72 #:text-inset 0.0 ,meta-value)
             (overlay #:id ,(component-child-id id-value 'divider) #:x ,x-value #:y ,(+ y-value height-value -1)
                      #:width ,width-value #:height 1 #:background (theme-color border-subtle) #:opacity 1.0 #:z 8))
          stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'page-header "expected fixed x/y/width, stable IDs and static typography" stx)]))

  (define (parse-metric-tile stx seen)
    (syntax-parse stx
      #:datum-literals (metric-tile)
      [(metric-tile #:id id:id #:label-id label-id:id #:value-id value-id:id
                    #:label label #:value value #:font-face face:id #:x x #:y y #:width width
                    (~optional (~seq #:height height) #:defaults ([height #'72]))
                    (~optional (~seq #:background background) #:defaults ([background #'(theme-color surface)]))
                    (~optional (~seq #:accent accent) #:defaults ([accent #'(theme-color accent)])))
       (define id-value (syntax-e #'id))
       (define x-value (expect-number 'metric-tile #'x))
       (define y-value (expect-number 'metric-tile #'y))
       (define width-value (expect-positive-integer 'metric-tile #'width))
       (define height-value (expect-positive-integer 'metric-tile #'height))
       (define label-value (component-literal-string 'metric-tile #'label))
       (define metric-value (component-literal-string 'metric-tile #'value))
       (define lowered
         (datum->syntax
          stx
          `(stack #:id ,id-value #:x ,x-value #:y ,y-value #:width ,width-value #:height ,height-value
                  #:radius (theme-radius card) #:background ,(syntax->datum #'background)
             (overlay #:id ,(component-child-id id-value 'accent) #:x ,x-value #:y ,y-value #:width 4 #:height ,height-value
                      #:background ,(syntax->datum #'accent) #:opacity 1.0 #:z 5)
             (text #:id ,(syntax-e #'label-id) #:x ,(+ x-value 18) #:y ,(+ y-value 8)
                   #:width ,(- width-value 30) #:height 18 #:font-face ,(syntax-e #'face)
                   #:font-scale 0.72 #:text-inset 0.0 ,label-value)
             (text #:id ,(syntax-e #'value-id) #:x ,(+ x-value 18) #:y ,(+ y-value 27)
                   #:width ,(- width-value 30) #:height 34 #:font-face ,(syntax-e #'face)
                   #:font-scale 0.82 #:text-inset 0.0 ,metric-value)
             (overlay #:id ,(component-child-id id-value 'border) #:x ,x-value #:y ,(+ y-value height-value -1)
                      #:width ,width-value #:height 1 #:background (theme-color border-subtle) #:opacity 1.0 #:z 6))
          stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'metric-tile "expected stable IDs, static label/value, font face and fixed geometry" stx)]))

  (define (parse-action-button-v2 stx seen)
    (syntax-parse stx
      #:datum-literals (action-button)
      [(action-button #:id id:id #:button-id button-id:id #:label-id label-id:id
                      #:label label #:font-face face:id #:on action:id #:x x #:y y
                      (~optional (~seq #:width width) #:defaults ([width #'176]))
                      (~optional (~seq #:height height) #:defaults ([height #'40]))
                      (~optional (~seq #:variant variant:id) #:defaults ([variant #'filled])))
       (define id-value (syntax-e #'id))
       (define x-value (expect-number 'action-button #'x))
       (define y-value (expect-number 'action-button #'y))
       (define width-value (expect-positive-integer 'action-button #'width))
       (define height-value (expect-positive-integer 'action-button #'height))
       (define variant-value (syntax-e #'variant))
       (unless (memq variant-value '(filled outline))
         (raise-syntax-error 'action-button "#:variant must be filled or outline" #'variant))
       (define label-value (component-literal-string 'action-button #'label))
       (define fill (if (eq? variant-value 'filled) '(theme-color accent) '(theme-color surface-raised)))
       (define border (if (eq? variant-value 'filled) '(theme-color accent) '(theme-color border-strong)))
       (define lowered
         (datum->syntax
          stx
          `(stack #:id ,id-value #:x ,x-value #:y ,y-value #:width ,width-value #:height ,height-value
                  #:background ,fill
             (button #:id ,(syntax-e #'button-id) #:x ,x-value #:y ,y-value #:width ,width-value #:height ,height-value
                     #:radius (theme-radius card) #:background ,fill ,label-value #:on ,(syntax-e #'action))
             (text #:id ,(syntax-e #'label-id) #:x ,(+ x-value 12) #:y ,(+ y-value 6)
                   #:width ,(- width-value 24) #:height ,(- height-value 12) #:font-face ,(syntax-e #'face)
                   #:font-scale 0.72 #:text-inset 0.0 ,label-value)
             (overlay #:id ,(component-child-id id-value 'border) #:x ,x-value #:y ,(+ y-value height-value -1)
                      #:width ,width-value #:height 1 #:background ,border #:opacity 1.0 #:z 10))
          stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'action-button "expected stable IDs, static label, action and fixed geometry" stx)]))

  ;; Material Profile v1 components are syntax compression over the existing
  ;; primitive grammar. They intentionally omit ripple, free reflow, icon lookup,
  ;; runtime theme switching, and arbitrary motion.
  (define (parse-material-app-bar stx seen)
    (syntax-parse stx
      #:datum-literals (material-app-bar)
      [(material-app-bar #:id id:id #:title-id title-id:id #:title title #:font-face face:id
                         #:x x #:y y #:width width
                         (~optional (~seq #:height height) #:defaults ([height #'64]))
                         (~optional (~seq #:background background) #:defaults ([background #'(theme-color surface-container)])))
       (define id-value (syntax-e #'id))
       (define x-value (expect-number 'material-app-bar #'x))
       (define y-value (expect-number 'material-app-bar #'y))
       (define width-value (expect-positive-integer 'material-app-bar #'width))
       (define height-value (expect-positive-integer 'material-app-bar #'height))
       (define title-value (component-literal-string 'material-app-bar #'title))
       (define lowered
         (datum->syntax stx
                        `(surface #:id ,id-value #:x ,x-value #:y ,y-value
                                  #:width ,width-value #:height ,height-value
                                  #:background ,(syntax->datum #'background)
                                  #:elevation (theme-elevation level-0) #:clip #t
                           (text #:id ,(syntax-e #'title-id) #:x 24 #:y 17
                                 #:width ,(- width-value 48) #:height 30 #:font-face ,(syntax-e #'face)
                                 #:font-scale 0.82 #:text-inset 0.0 ,title-value)
                           (overlay #:id ,(component-child-id id-value 'separator)
                                    #:x 0 #:y ,(- height-value 1) #:width ,width-value #:height 1
                                    #:background (theme-color outline-variant) #:opacity 1.0 #:z 8))
                        stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'material-app-bar
                             "expected a fixed title, font face and x/y/width geometry" stx)]))

  (define (parse-material-card stx seen)
    (syntax-parse stx
      #:datum-literals (material-card)
      [(material-card #:id id:id #:x x #:y y #:width width #:height height
                      (~optional (~seq #:background background) #:defaults ([background #'(theme-color surface-container-low)]))
                      (~optional (~seq #:elevation elevation) #:defaults ([elevation #'(theme-elevation level-1)]))
                      child:expr ...+)
       (define id-value (syntax-e #'id))
       (define x-value (expect-number 'material-card #'x))
       (define y-value (expect-number 'material-card #'y))
       (define width-value (expect-positive-integer 'material-card #'width))
       (define height-value (expect-positive-integer 'material-card #'height))
       (define lowered
         (datum->syntax stx
                        `(surface #:id ,id-value #:x ,x-value #:y ,y-value #:width ,width-value #:height ,height-value
                                  #:background ,(syntax->datum #'background)
                                  #:elevation ,(syntax->datum #'elevation) #:radius (theme-radius card) #:clip #t
                           ,@(map syntax->datum (syntax->list #'(child ...))))
                        stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'material-card
                             "expected fixed x/y/width/height geometry and one or more primitive children" stx)]))

  (define (parse-material-filled-button stx seen)
    (syntax-parse stx
      #:datum-literals (material-filled-button)
      [(material-filled-button #:id id:id #:button-id button-id:id #:label-id label-id:id
                               #:label label #:font-face face:id #:on action:id #:x x #:y y
                               (~optional (~seq #:width width) #:defaults ([width #'120]))
                               (~optional (~seq #:height height) #:defaults ([height #'40])))
       (define id-value (syntax-e #'id))
       (define x-value (expect-number 'material-filled-button #'x))
       (define y-value (expect-number 'material-filled-button #'y))
       (define width-value (expect-positive-integer 'material-filled-button #'width))
       (define height-value (expect-positive-integer 'material-filled-button #'height))
       (define label-value (component-literal-string 'material-filled-button #'label))
       (define lowered
         (datum->syntax stx
                        `(stack #:id ,id-value #:x ,x-value #:y ,y-value #:width ,width-value #:height ,height-value
                                #:background (theme-color primary)
                           (button #:id ,(syntax-e #'button-id) #:x ,x-value #:y ,y-value
                                   #:width ,width-value #:height ,height-value #:radius (theme-radius control)
                                   #:background (theme-color primary) ,label-value #:on ,(syntax-e #'action))
                           (text #:id ,(syntax-e #'label-id) #:x ,(+ x-value 16) #:y ,(+ y-value 7)
                                 #:width ,(- width-value 32) #:height ,(- height-value 14)
                                 #:font-face ,(syntax-e #'face) #:font-scale 0.72 #:text-inset 0.0 ,label-value))
                        stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'material-filled-button
                             "expected stable IDs, static label/action, font face and fixed geometry" stx)]))

  (define (parse-material-nav-destination form active-id face x y width index)
    (syntax-parse form
      #:datum-literals (material-destination)
      [(material-destination #:id id:id #:label-id label-id:id #:label label)
       (define destination-id (syntax-e #'id))
       (define selected? (eq? destination-id active-id))
       (define label-value (component-literal-string 'material-destination #'label))
       (define row-y (+ y 24 (* index 64)))
       (append
        `(stack #:id ,destination-id #:x ,(+ x 12) #:y ,row-y #:width ,(- width 24) #:height 48
                #:visual-anchor #t)
        (if selected? (list '#:radius '(theme-radius control)) '())
        `(#:background ,(if selected? '(theme-color secondary-container) '(theme-color surface-container))
          (text #:id ,(syntax-e #'label-id) #:x 12 #:y 15
                #:width ,(- width 48) #:height 20 #:font-face ,face
                #:font-scale 0.72 #:text-inset 0.0 ,label-value)))]
      [_ (raise-syntax-error 'material-nav-rail
                             "each child must be (material-destination #:id id #:label-id id #:label string)" form)]))

  (define (parse-material-nav-rail stx seen)
    (syntax-parse stx
      #:datum-literals (material-nav-rail)
      [(material-nav-rail #:id id:id #:active active:id #:font-face face:id #:x x #:y y #:width width #:height height
                          destination:expr ...+)
       (define id-value (syntax-e #'id))
       (define active-value (syntax-e #'active))
       (define x-value (expect-number 'material-nav-rail #'x))
       (define y-value (expect-number 'material-nav-rail #'y))
       (define width-value (expect-positive-integer 'material-nav-rail #'width))
       (define height-value (expect-positive-integer 'material-nav-rail #'height))
       (unless (>= width-value 72)
         (raise-syntax-error 'material-nav-rail "#:width must be at least 72px" #'width))
       (define destination-forms (syntax->list #'(destination ...)))
       (unless (<= 3 (length destination-forms) 7)
         (raise-syntax-error 'material-nav-rail "requires 3 to 7 literal material-destination children" stx))
       (define destination-datums
         (for/list ([form (in-list destination-forms)] [index (in-naturals)])
           (parse-material-nav-destination form active-value (syntax-e #'face)
                                           x-value y-value width-value index)))
       (unless (ormap (lambda (datum) (eq? (caddr datum) active-value)) destination-datums)
         (raise-syntax-error 'material-nav-rail "#:active must name one declared material-destination" #'active))
       (define lowered
         (datum->syntax stx
                        `(surface #:id ,id-value #:x ,x-value #:y ,y-value #:width ,width-value #:height ,height-value
                                  #:background (theme-color surface-container) #:elevation (theme-elevation level-0)
                                  #:radius (theme-radius panel) #:clip #t
                           ,@destination-datums)
                        stx stx))
       (parse-node lowered seen)]
      [_ (raise-syntax-error 'material-nav-rail
                             "expected fixed rail geometry, active destination, font face and 3–7 destinations" stx)]))

  ;; `repeat/ui` 只接受固定的 datum table：
  ;; (repeat/ui ((id state label)
  ;;             (cpu-0 cpu0 "CPU 0")
  ;;             (cpu-1 cpu1 "CPU 1"))
  ;;   (metric-card #:id id #:label label #:dynamic state #:max-chars 3))
  ;; row table、template 与 substitution 均发生在 macro expansion；没有 runtime loop/key/diff。
  (define (repeat-substitute datum replacements)
    (cond
      [(symbol? datum) (hash-ref replacements datum datum)]
      [(pair? datum) (map (lambda (item) (repeat-substitute item replacements)) datum)]
      [(vector? datum) (list->vector (map (lambda (item) (repeat-substitute item replacements))
                                          (vector->list datum)))]
      [else datum]))
  (define (parse-repeat-ui stx seen)
    (syntax-parse stx
      #:datum-literals (repeat/ui)
      [(repeat/ui ((binding:id ...) (row ...) ...) body)
       (define bindings (map syntax-e (syntax->list #'(binding ...))))
       (when (null? bindings)
         (raise-syntax-error 'repeat/ui "binding table needs at least one identifier" stx))
       (define rows (syntax->list #'((row ...) ...)))
       (when (null? rows)
         (raise-syntax-error 'repeat/ui "static sequence needs at least one row" stx))
       (let loop ([remaining rows] [seen seen] [nodes '()] [index 0])
         (cond
           [(null? remaining) (values (reverse nodes) seen)]
           [else
            (define row-values (syntax->list (car remaining)))
            (unless (= (length row-values) (length bindings))
              (raise-syntax-error 'repeat/ui
                                  (format "row ~a has ~a values; expected ~a" index (length row-values) (length bindings))
                                  (car remaining)))
            (define replacements
              (for/hash ([binding (in-list bindings)] [value (in-list row-values)])
                (values binding (syntax->datum value))))
            (define lowered
              (datum->syntax #'body
                             (repeat-substitute (syntax->datum #'body) replacements)
                             stx stx))
            (define-values (node seen*) (parse-node lowered seen))
            (loop (cdr remaining) seen* (cons node nodes) (+ index 1))]))]
      [_ (raise-syntax-error 'repeat/ui
                             "expected (repeat/ui ((binding ...) (value ...) ...) single-child-template)"
                             stx)]))

  ;; (virtual-list #:id telemetry #:capacity 8 #:visible-rows 3 #:row-height 28 #:max-chars 8
  ;;   (row-template ((node-0 "NODE ZERO") ...)))
  ;; The row table is a compile-time literal.  Capacity is fixed even when only
  ;; visible-rows are clipped; no runtime iterator, key lookup or geometry solve exists.
  (define (parse-virtual-list stx seen)
    (syntax-parse stx
      #:datum-literals (virtual-list row-template data-table data-register-table data-update-batch on-activate)
      ;; Compact register form with a compiler-fixed data update batch.
      [(virtual-list #:id id:id #:logical-capacity logical-capacity #:physical-slots physical-slots
                     #:visible-rows visible #:row-height row-height #:max-chars max-chars
(data-register-table #:id table-id:id
                        (~optional (~seq #:font-face font-face:id) #:defaults ([font-face #'#f]))
                        #:seed seed-label
                        (data-update-batch #:id batch-id:id ((update-index update-value) ...+)))
                     (~optional (on-activate activate-action:id) #:defaults ([activate-action #'#f]))
                     (row-template ((row-id:id row-label) ...+)))
       (define id-value (syntax-e #'id))
       (define logical-capacity-value (expect-positive-integer 'virtual-list #'logical-capacity))
       (define physical-slots-value (expect-positive-integer 'virtual-list #'physical-slots))
       (define visible-value (expect-positive-integer 'virtual-list #'visible))
       (define row-height-value (expect-positive-integer 'virtual-list #'row-height))
       (define max-chars-value (expect-positive-integer 'virtual-list #'max-chars))
       (unless (<= visible-value physical-slots-value logical-capacity-value)
         (raise-syntax-error 'virtual-list "requires visible-rows <= physical-slots <= logical-capacity" stx))
               (define seed-value (component-literal-string 'data-register-table #'seed-label))
        (define table-face (and (syntax-e #'font-face) (symbol->string (syntax-e #'font-face))))
        (when table-face
          (define asset (current-static-dynamic-font-cell-asset))
          (unless (and asset (string=? table-face (c-dynamic-font-cell-asset-face-id asset)))
            (raise-syntax-error 'data-register-table "#:font-face must name the declared dynamic-font-cell-asset" #'font-face)))
        (define update-indices (map syntax-e (syntax->list #'(update-index ...))))
       (unless (andmap exact-nonnegative-integer? update-indices)
         (raise-syntax-error 'data-update-batch "every update index must be a non-negative integer literal" stx))
       (unless (= (length update-indices) (length (remove-duplicates update-indices)))
         (raise-syntax-error 'data-update-batch "duplicate logical update index" stx))
       (unless (andmap (lambda (index) (< index logical-capacity-value)) update-indices)
         (raise-syntax-error 'data-update-batch "update index exceeds virtual-list logical capacity" stx))
       (define update-values (map (lambda (value-stx) (component-literal-string 'data-update-batch value-stx)) (syntax->list #'(update-value ...))))
       (for ([value (in-list update-values)])
         (unless (and (<= (string-length value) max-chars-value)
                      (for/and ([ch (in-string value)]) (or (char=? ch #\space) (char-numeric? ch) (char<=? #\A ch #\Z))))
           (raise-syntax-error 'data-update-batch "updates require fixed-width uppercase ASCII values" stx)))
       (define row-ids (map syntax-e (syntax->list #'(row-id ...))))
       (define row-labels (map (lambda (label-stx) (component-literal-string 'row-template label-stx)) (syntax->list #'(row-label ...))))
       (unless (= (length row-ids) physical-slots-value)
         (raise-syntax-error 'virtual-list "row-template must provide exactly #:physical-slots physical rows" stx))
       (define-values (outer-id ignored seen*) (register-id 'virtual-list stx (hash '#:id id-value) seen))
       (define row-forms
         (for/list ([row-id (in-list row-ids)] [label (in-list row-labels)])
           (define fixed-label (if table-face
                                   (string-append label (make-string (- max-chars-value (string-length label)) #\space))
                                   label))
           `(row #:id ,row-id #:height ,row-height-value
                 (text #:id ,(component-child-id row-id 'label) ,fixed-label))))
       (define-values (rows seen**) (parse-children (map (lambda (form) (datum->syntax stx form stx stx)) row-forms) seen*))
       (define props (hash 'capacity physical-slots-value 'logical-capacity logical-capacity-value 'physical-slots physical-slots-value
                           'recycling? #t 'logical-data-ids '() 'logical-labels '() 'visible-rows visible-value
                           'row-height row-height-value 'max-chars max-chars-value 'viewport-height (* visible-value row-height-value)
                           'row-ids row-ids '#:clip #t
                           'data-register-table (hash 'id (syntax-e #'table-id) 'capacity logical-capacity-value 'register-width max-chars-value 'seed seed-value
                                                       'atlas-page (if table-face 3 ascii-atlas-page) 'font-face table-face)
                            'data-update-batches (list (hash 'id (syntax-e #'batch-id) 'table (syntax-e #'table-id)
                                                           'updates (for/list ([index (in-list update-indices)] [value (in-list update-values)]) (hash 'index index 'value value))))
                           'on-activate (syntax-e #'activate-action)))
       (values (c-node 'virtual-list outer-id props rows stx) seen**)]
      ;; Compact register form: no logical labels or per-viewport transition table is expanded.
      [(virtual-list #:id id:id #:logical-capacity logical-capacity #:physical-slots physical-slots
                     #:visible-rows visible #:row-height row-height #:max-chars max-chars
(data-register-table #:id table-id:id
                        (~optional (~seq #:font-face font-face:id) #:defaults ([font-face #'#f]))
                        #:seed seed-label)
                      (row-template ((row-id:id row-label) ...+)))
       (define id-value (syntax-e #'id))
       (define logical-capacity-value (expect-positive-integer 'virtual-list #'logical-capacity))
       (define physical-slots-value (expect-positive-integer 'virtual-list #'physical-slots))
       (define visible-value (expect-positive-integer 'virtual-list #'visible))
       (define row-height-value (expect-positive-integer 'virtual-list #'row-height))
       (define max-chars-value (expect-positive-integer 'virtual-list #'max-chars))
       (unless (<= visible-value physical-slots-value logical-capacity-value)
         (raise-syntax-error 'virtual-list "requires visible-rows <= physical-slots <= logical-capacity" stx))
        (define seed-value (component-literal-string 'data-register-table #'seed-label))
        (define table-face (and (syntax-e #'font-face) (symbol->string (syntax-e #'font-face))))
        (when table-face
          (define asset (current-static-dynamic-font-cell-asset))
          (unless (and asset (string=? table-face (c-dynamic-font-cell-asset-face-id asset)))
            (raise-syntax-error 'data-register-table "#:font-face must name the declared dynamic-font-cell-asset" #'font-face)))
        (unless (<= (string-length seed-value) max-chars-value)
         (raise-syntax-error 'virtual-list "data-register-table seed exceeds #:max-chars" #'seed-label))
       (define row-ids (map syntax-e (syntax->list #'(row-id ...))))
       (define row-labels (map (lambda (label-stx) (component-literal-string 'row-template label-stx))
                               (syntax->list #'(row-label ...))))
       (unless (= (length row-ids) physical-slots-value)
         (raise-syntax-error 'virtual-list "row-template must provide exactly #:physical-slots physical rows" stx))
       (define-values (outer-id ignored seen*) (register-id 'virtual-list stx (hash '#:id id-value) seen))
       (define row-forms
         (for/list ([row-id (in-list row-ids)] [label (in-list row-labels)])
           (define fixed-label (if table-face
                                   (string-append label (make-string (- max-chars-value (string-length label)) #\space))
                                   label))
           `(row #:id ,row-id #:height ,row-height-value
                 (text #:id ,(component-child-id row-id 'label) ,fixed-label))))
       (define-values (rows seen**) (parse-children (map (lambda (form) (datum->syntax stx form stx stx)) row-forms) seen*))
       (define props
         (hash 'capacity physical-slots-value 'logical-capacity logical-capacity-value 'physical-slots physical-slots-value
               'recycling? #t 'logical-data-ids '() 'logical-labels '() 'visible-rows visible-value
               'row-height row-height-value 'max-chars max-chars-value 'viewport-height (* visible-value row-height-value)
               'row-ids row-ids '#:clip #t
'data-register-table (hash 'id (syntax-e #'table-id) 'capacity logical-capacity-value
                                           'register-width max-chars-value 'seed seed-value
                                           'atlas-page (if table-face 3 ascii-atlas-page) 'font-face table-face)))
       (values (c-node 'virtual-list outer-id props rows stx) seen**)]
      ;; Recycling form: logical data is a fixed compile-time table while the row-template
      ;; materializes only physical GPU slots. Runtime may rotate slots but never allocates rows.
      [(virtual-list #:id id:id #:logical-capacity logical-capacity #:physical-slots physical-slots
                     #:visible-rows visible #:row-height row-height #:max-chars max-chars
                     (~or (data-table ((data-id:id data-label) ...+))
                           (data-register-table ((data-id:id data-label) ...+)))
                     (row-template ((row-id:id seed-label) ...+)))
       (define id-value (syntax-e #'id))
       (define logical-capacity-value (expect-positive-integer 'virtual-list #'logical-capacity))
       (define physical-slots-value (expect-positive-integer 'virtual-list #'physical-slots))
       (define visible-value (expect-positive-integer 'virtual-list #'visible))
       (define row-height-value (expect-positive-integer 'virtual-list #'row-height))
       (define max-chars-value (expect-positive-integer 'virtual-list #'max-chars))
       (unless (<= visible-value physical-slots-value)
         (raise-syntax-error 'virtual-list "#:visible-rows cannot exceed #:physical-slots" #'visible))
       (unless (<= physical-slots-value logical-capacity-value)
         (raise-syntax-error 'virtual-list "#:physical-slots cannot exceed #:logical-capacity" #'physical-slots))
       (define data-ids (map syntax-e (syntax->list #'(data-id ...))))
       (define data-labels (map (lambda (label-stx) (component-literal-string 'data-register-table label-stx))
                                (syntax->list #'(data-label ...))))
       (define row-ids (map syntax-e (syntax->list #'(row-id ...))))
       (define seed-labels (map (lambda (label-stx) (component-literal-string 'row-template label-stx))
                                (syntax->list #'(seed-label ...))))
       (unless (= (length data-ids) logical-capacity-value)
         (raise-syntax-error 'virtual-list "data-register-table must provide exactly #:logical-capacity literal rows" stx))
       (unless (= (length row-ids) physical-slots-value)
         (raise-syntax-error 'virtual-list "row-template must provide exactly #:physical-slots physical rows" stx))
       (for ([label (in-list data-labels)])
         (unless (<= (string-length label) max-chars-value)
           (raise-syntax-error 'virtual-list "data-register-table label exceeds #:max-chars" stx)))
       (define-values (outer-id ignored seen*)
         (register-id 'virtual-list stx (hash '#:id id-value) seen))
       (define row-forms
         (for/list ([row-id (in-list row-ids)] [data-label (in-list data-labels)])
           `(row #:id ,row-id #:height ,row-height-value
                 (text #:id ,(component-child-id row-id 'label) ,data-label))))
       (define-values (rows seen**)
         (parse-children (map (lambda (form) (datum->syntax stx form stx stx)) row-forms) seen*))
       (define props
         (hash 'capacity physical-slots-value
               'logical-capacity logical-capacity-value
               'physical-slots physical-slots-value
               'recycling? #t
               'logical-data-ids data-ids
               'logical-labels data-labels
               'visible-rows visible-value
               'row-height row-height-value
               'max-chars max-chars-value
               'viewport-height (* visible-value row-height-value)
               'row-ids row-ids
               '#:clip #t))
       (values (c-node 'virtual-list outer-id props rows stx) seen**)]
      [(virtual-list #:id id:id #:capacity capacity #:visible-rows visible #:row-height row-height #:max-chars max-chars
                     (row-template ((row-id:id label) ...+)))
       (define id-value (syntax-e #'id))
       (define capacity-value (expect-positive-integer 'virtual-list #'capacity))
       (define visible-value (expect-positive-integer 'virtual-list #'visible))
       (define row-height-value (expect-positive-integer 'virtual-list #'row-height))
       (define max-chars-value (expect-positive-integer 'virtual-list #'max-chars))
       (unless (<= visible-value capacity-value)
         (raise-syntax-error 'virtual-list "#:visible-rows cannot exceed #:capacity" #'visible))
       (define row-ids (map syntax-e (syntax->list #'(row-id ...))))
       (define labels (map (lambda (label-stx) (component-literal-string 'row-template label-stx))
                           (syntax->list #'(label ...))))
       (unless (= (length row-ids) capacity-value)
         (raise-syntax-error 'virtual-list "row-template must provide exactly #:capacity literal rows" stx))
       (for ([label (in-list labels)])
         (unless (<= (string-length label) max-chars-value)
           (raise-syntax-error 'virtual-list "row-template label exceeds #:max-chars" stx)))
       (define-values (outer-id ignored seen*)
         (register-id 'virtual-list stx (hash '#:id id-value) seen))
       (define row-forms
         (for/list ([row-id (in-list row-ids)] [label (in-list labels)])
           `(row #:id ,row-id #:height ,row-height-value
                 (text #:id ,(component-child-id row-id 'label) ,label))))
       (define-values (rows seen**)
         (parse-children (map (lambda (form) (datum->syntax stx form stx stx)) row-forms) seen*))
       (define props
         (hash 'capacity capacity-value
               'visible-rows visible-value
               'row-height row-height-value
               'max-chars max-chars-value
               'viewport-height (* visible-value row-height-value)
               'row-ids row-ids
               '#:clip #t))
       (values (c-node 'virtual-list outer-id props rows stx) seen**)]
      [_ (raise-syntax-error 'virtual-list
                             "expected (virtual-list #:id id #:capacity positive-int #:visible-rows positive-int #:row-height positive-int #:max-chars positive-int (row-template ((row-id \\\"STATIC LABEL\\\") ...)))"
                             stx)]))

  (define (parse-scrollbar stx forms seen)
    ;; v1 intentionally uses literal geometry. The host receives one fixed track rect,
    ;; one fixed thumb instance address, and a pre-proved list reference; it never measures.
    (syntax-parse stx
      [(scrollbar #:id id:id #:for list-id:id #:x x #:y y #:width width #:height height #:thumb-height thumb-height)
       (define id-value (syntax-e #'id))
       (define list-id-value (syntax-e #'list-id))
       (define x-value (expect-nonnegative-integer 'scrollbar #'x))
       (define y-value (expect-nonnegative-integer 'scrollbar #'y))
       (define width-value (expect-positive-integer 'scrollbar #'width))
       (define height-value (expect-positive-integer 'scrollbar #'height))
       (define thumb-height-value (expect-positive-integer 'scrollbar #'thumb-height))
       (unless (<= thumb-height-value height-value)
         (raise-syntax-error 'scrollbar "#:thumb-height cannot exceed #:height" #'thumb-height))
       (define-values (outer-id ignored seen*)
         (register-id 'scrollbar stx (hash '#:id id-value) seen))
       (define thumb-id (component-child-id outer-id 'thumb))
       (define thumb
         (c-node 'scrollbar-thumb thumb-id
                 (hash '#:x 0 '#:y 0 '#:width width-value '#:height thumb-height-value)
                 '() stx))
       (values (c-node 'scrollbar outer-id
                       (hash 'list-id list-id-value '#:x x-value '#:y y-value
                             '#:width width-value '#:height height-value
                             'thumb-height thumb-height-value)
                       (list thumb) stx)
               seen*)]
      [_ (raise-syntax-error 'scrollbar
                             "expected (scrollbar #:id id #:for virtual-list-id #:x nonnegative-int #:y nonnegative-int #:width positive-int #:height positive-int #:thumb-height positive-int)"
                             stx)]))

  (define (parse-progress stx forms seen)
    ;; (progress #:id throughput #:dynamic progress #:max 100)
    ;; 语法有意受限：动态值只能改变已编译 rect 的 size.x，不能触发布局重排。
    (define allowed leaf-props)
    (let loop ([rest forms] [props (hash)] [dynamic-value #f])
      (cond
        [(null? rest)
         (unless dynamic-value
           (raise-syntax-error 'progress "progress needs #:dynamic state-id" stx))
         (unless (hash-has-key? props '#:max)
           (raise-syntax-error 'progress "progress needs #:max positive-integer" stx))
         (define-values (id clean-props seen*) (register-id 'progress stx props seen))
         (values (c-node 'progress id
                         (hash-set (hash-set (hash-remove clean-props '#:max)
                                              'value `(dynamic ,dynamic-value))
                                   'max (hash-ref props '#:max))
                         '() stx)
                 seen*)]
        [(keyword-stx? (car rest))
         (when (null? (cdr rest))
           (raise-syntax-error 'progress "property keyword needs a value" (car rest)))
         (define kw (syntax-e (car rest)))
         (cond
           [(eq? kw '#:dynamic)
            (when dynamic-value
              (raise-syntax-error 'progress "duplicate #:dynamic" (car rest)))
            (loop (cddr rest) props (expect-symbol 'progress (cadr rest)))]
           [else
            (unless (set-member? allowed kw)
              (raise-syntax-error 'progress (format "property ~a is not allowed here" kw) (car rest)))
            (when (hash-has-key? props kw)
              (raise-syntax-error 'progress (format "duplicate property ~a" kw) (car rest)))
            (loop (cddr rest) (hash-set props kw (property-value 'progress kw (cadr rest))) dynamic-value)])]
        [else (raise-syntax-error 'progress "progress has no positional children" (car rest))])))

  (define (parse-overlay stx forms seen)
    ;; 半透明 overlay 是受限叶子：无子节点、固定 rect、由 #lang 宏决定 z/clip 语义。
    (define-values (props rest) (parse-props 'overlay forms leaf-props))
    (when (pair? rest)
      (raise-syntax-error 'overlay "overlay cannot have child forms" (car rest)))
    (unless (hash-has-key? props '#:opacity)
      (raise-syntax-error 'overlay "overlay needs a literal #:opacity" stx))
    (define-values (id clean-props seen*) (register-id 'overlay stx props seen))
    (values (c-node 'overlay id clean-props '() stx) seen*))

  (define (parse-spacer stx forms seen)
    (define-values (props rest) (parse-props 'spacer forms leaf-props))
    (when (pair? rest)
      (raise-syntax-error 'spacer "spacer cannot have child forms" (car rest)))
    (define-values (id clean-props seen*) (register-id 'spacer stx props seen))
    (values (c-node 'spacer id clean-props '() stx) seen*))

  (define (parse-node stx seen)
    (syntax-parse stx
#:datum-literals (row column stack grid text text-field button transaction-button multi-field-event multi-action-event virtual-list scrollbar control-button metric-card form-row settings-form app-shell surface divider status-indicator toolbar table-header status-pill detail-panel workspace-shell page-header metric-tile action-button material-app-bar material-card material-filled-button material-nav-rail material-destination repeat/ui progress overlay spacer)
        [(app-shell form ...) (parse-app-shell stx seen)]
        [(surface form ...) (parse-surface stx seen)]
        [(divider form ...) (parse-divider stx seen)]
        [(status-indicator form ...) (parse-status-indicator stx seen)]
        [(toolbar form ...) (parse-toolbar stx seen)]
        [(table-header form ...) (parse-table-header stx seen)]
        [(status-pill form ...) (parse-status-pill stx seen)]
        [(detail-panel form ...) (parse-detail-panel stx seen)]
        [(workspace-shell form ...) (parse-workspace-shell stx seen)]
        [(page-header form ...) (parse-page-header stx seen)]
        [(metric-tile form ...) (parse-metric-tile stx seen)]
        [(action-button form ...) (parse-action-button-v2 stx seen)]
        [(material-app-bar form ...) (parse-material-app-bar stx seen)]
        [(material-card form ...) (parse-material-card stx seen)]
        [(material-filled-button form ...) (parse-material-filled-button stx seen)]
        [(material-nav-rail form ...) (parse-material-nav-rail stx seen)]
        [(form-row form ...) (parse-form-row stx seen)]
       [(settings-form form ...) (parse-settings-form stx seen)]
       [(metric-card form ...) (parse-metric-card stx seen)]
      [(control-button form ...) (parse-control-button stx seen)]
      [(text-field form ...) (parse-text-field stx seen)]
      [(row form ...)    (parse-layout 'row stx (syntax->list #'(form ...)) seen)]
      [(column form ...) (parse-layout 'column stx (syntax->list #'(form ...)) seen)]
      [(stack form ...)  (parse-layout 'stack stx (syntax->list #'(form ...)) seen)]
      [(grid form ...)   (parse-layout 'grid stx (syntax->list #'(form ...)) seen)]
      [(text form ...)   (parse-text stx (syntax->list #'(form ...)) seen)]
       [(transaction-button form ...) (parse-transaction-button stx seen)]
       [(multi-field-event form ...) (parse-multi-field-event stx seen)]
       [(multi-action-event form ...) (parse-multi-action-event stx seen)]
       [(virtual-list form ...) (parse-virtual-list stx seen)]
       [(scrollbar form ...) (parse-scrollbar stx (syntax->list #'(form ...)) seen)]
       [(button form ...) (parse-button stx (syntax->list #'(form ...)) seen)]
      [(progress form ...) (parse-progress stx (syntax->list #'(form ...)) seen)]
      [(overlay form ...) (parse-overlay stx (syntax->list #'(form ...)) seen)]
      [(spacer form ...) (parse-spacer stx (syntax->list #'(form ...)) seen)]
      [_ (raise-syntax-error 'ui
                             "expected an established primitive, desktop component, or Material Profile v1 component as a layout child"
                             stx)]))

  (define (dynamic-node? n)
    ;; DSL 中 opacity/width/height 均要求 literal，属于编译期合成或几何常量；
    ;; 只有显式 dynamic text/progress 才进入 runtime 状态依赖图。
    (and (memq (c-node-tag n) '(text progress))
         (pair? (hash-ref (c-node-props n) 'value #f))))

  (define (count-nodes n)
    (+ 1 (for/sum ([child (in-list (c-node-children n))]) (count-nodes child))))

  (define (count-dynamic n)
    (+ (if (dynamic-node? n) 1 0)
       (for/sum ([child (in-list (c-node-children n))]) (count-dynamic child))))

  (define (collect-update-plan n)
    (append
     (if (and (eq? (c-node-tag n) 'text)
              (pair? (hash-ref (c-node-props n) 'value #f)))
         (list `(text-run-patch ,(c-node-id n) ,(hash-ref (c-node-props n) 'max-chars)))
         '())
     (if (eq? (c-node-tag n) 'progress)
         (list `(instance-patch ,(c-node-id n) size.x))
         '())
     (append-map collect-update-plan (c-node-children n))))

  (define (dynamic-text-state node)
    (define value (hash-ref (c-node-props node) 'value #f))
    (and (eq? (c-node-tag node) 'text)
         (pair? value) (eq? (first value) 'dynamic) (second value)))

  (define (dynamic-progress-state node)
    (define value (hash-ref (c-node-props node) 'value #f))
    (and (eq? (c-node-tag node) 'progress)
         (pair? value) (eq? (first value) 'dynamic) (second value)))

  (define (walk-nodes node)
    (cons node (append-map walk-nodes (c-node-children node))))

  ;; buffer range 在 compiler 中顺序分配；runtime 只接收 offset/length，
  ;; 不负责寻址或重新布局。这正是局部更新语义的第一层证据。
  ;; Compact data-register rows own fixed glyph cells that are mutable through the
  ;; register ABI, not through a declared UI state. This marks that distinct source
  ;; of mutability without adding a runtime lookup or a synthetic state dependency.
  (define (dynamic-font-cell-text-node-ids root face-id)
    (for/fold ([ids (set)]) ([list-node (in-list (walk-nodes root))]
                              #:when (and (eq? (c-node-tag list-node) 'virtual-list)
                                          (let ([table (hash-ref (c-node-props list-node) 'data-register-table #f)])
                                            (and table (equal? (hash-ref table 'font-face #f) face-id)))))
      (for/fold ([row-ids ids]) ([child (in-list (c-node-children list-node))])
        (for/fold ([next-ids row-ids]) ([descendant (in-list (walk-nodes child))])
          (if (eq? (c-node-tag descendant) 'text)
              (set-add next-ids (c-node-id descendant))
              next-ids)))))

  (define (compact-register-text-node-ids root)
    (for/fold ([ids (set)]) ([list-node (in-list (walk-nodes root))]
                              #:when (and (eq? (c-node-tag list-node) 'virtual-list)
                                          (hash-ref (c-node-props list-node) 'data-register-table #f)))
      (for/fold ([row-ids ids]) ([child (in-list (c-node-children list-node))])
        (for/fold ([next-ids row-ids]) ([descendant (in-list (walk-nodes child))]
                                      #:when (eq? (c-node-tag descendant) 'text))
          (set-add next-ids (c-node-id descendant))))))

  (define (collect-glyph-bindings root)
    (define compact-register-ids (compact-register-text-node-ids root))
    (let loop ([nodes (walk-nodes root)] [offset 0] [result '()])
      (cond
        [(null? nodes) (reverse result)]
        [else
         (define node (car nodes))
         (define state-id (dynamic-text-state node))
         (define static-value (and (eq? (c-node-tag node) 'text)
                                   (hash-ref (c-node-props node) 'value #f)))
         (cond
           [state-id
            (define glyph-count (hash-ref (c-node-props node) 'max-chars))
            (define charset (hash-ref (c-node-props node) 'charset 'digits))
            (define byte-length (* glyph-count glyph-instance-bytes))
            (define binding (c-binding (c-node-id node) state-id #t offset byte-length glyph-count
                                       (if (eq? charset 'ascii-upper) ascii-atlas-page digit-atlas-page)
                                       (if (eq? charset 'ascii-upper) (make-list glyph-count (encode-glyph ascii-atlas-page 0)) '())
                                       (make-list glyph-count 1.0)
                                       #f))
            (loop (cdr nodes) (+ offset byte-length) (cons binding result))]
           [(string? static-value)
            (define selected-face (hash-ref (c-node-props node) 'font-face #f))
            (define-values (page glyph-ids advances face-id)
              (if selected-face
                  (shape-static-fontc 'text static-value selected-face (c-node-source node))
                  (shape-static-ascii 'text static-value (c-node-source node))))
            (define glyph-count (length glyph-ids))
            (define byte-length (* glyph-count glyph-instance-bytes))
            (define binding (c-binding (c-node-id node) #f (set-member? compact-register-ids (c-node-id node)) offset byte-length glyph-count
                                       page glyph-ids advances face-id))
            (loop (cdr nodes) (+ offset byte-length) (cons binding result))]
           [else (loop (cdr nodes) offset result)])])))

  (define (assert-non-overlapping-bindings! bindings root)
    ;; collect-glyph-bindings 按稳定 tree order 单调分配 offset；该显式检查
    ;; 将该性质变成 macro-level invariant，而非依赖后端的偶然行为。
    (let loop ([previous-end 0] [remaining bindings])
      (unless (null? remaining)
        (define binding (car remaining))
        (when (< (c-binding-offset binding) previous-end)
          (raise-syntax-error 'text
                              (format "overlapping glyph buffer range for node ~a" (c-binding-node-id binding))
                              (c-node-source root)))
        (loop (+ (c-binding-offset binding) (c-binding-byte-length binding))
              (cdr remaining)))))

  (define (collect-button-action-ids root)
    (for/list ([node (in-list (walk-nodes root))]
               #:when (and (hash-has-key? (c-node-props node) 'on)
                           (not (hash-has-key? (c-node-props node) '#:transaction-op))))
      (hash-ref (c-node-props node) 'on)))

  (define (compile-action-plans root states actions layouts action-indexes)
    (define declared-state-ids (list->set (map c-state-id states)))
    (define declared-action-ids (list->set (map c-action-id actions)))
    (define node-by-id (for/hash ([node (in-list (walk-nodes root))]) (values (c-node-id node) node)))
    (define layout-by-id (for/hash ([layout (in-list layouts)]) (values (c-layout-id layout) layout)))
    (for ([binding (in-list (collect-glyph-bindings root))]
          #:when (c-binding-state binding))
      (unless (set-member? declared-state-ids (c-binding-state binding))
        (raise-syntax-error 'text "#:dynamic refers to an undeclared state" (c-node-source root))))
    (for ([node (in-list (walk-nodes root))])
      (define progress-state (dynamic-progress-state node))
      (when (and progress-state (not (set-member? declared-state-ids progress-state)))
        (raise-syntax-error 'progress "#:dynamic refers to an undeclared state" (c-node-source node))))
    (for ([action-id (in-list (collect-button-action-ids root))])
      (unless (set-member? declared-action-ids action-id)
        (raise-syntax-error 'button "#:on refers to an undeclared action" (c-node-source root))))
    (define text-bindings (collect-glyph-bindings root))
    (assert-non-overlapping-bindings! text-bindings root)
    (define instance-bindings
      (for/list ([node (in-list (walk-nodes root))]
                 #:when (dynamic-progress-state node))
        (define layout (hash-ref layout-by-id (c-node-id node)))
        (c-instance-binding (c-node-id node)
                            (dynamic-progress-state node)
                            (hash-ref (c-node-props node) 'max)
                            layout)))
    (for/list ([action (in-list actions)])
      (define text-updates
        (for/list ([binding (in-list text-bindings)]
                   #:when (eq? (c-binding-state binding) (c-action-state action)))
          binding))
      (define geometry-updates
        (for/list ([binding (in-list instance-bindings)]
                   #:when (eq? (c-instance-binding-state binding) (c-action-state action)))
          binding))
      ;; 进度条的 maximum rect 就是保守 Damage Plan；动作不求新布局，只标记
      ;; 固定 slot 的旧/新宽度可能覆盖的完整区域。
      (define damage (map c-instance-binding-layout geometry-updates))
      (c-action-plan (c-action-id action) action (hash-ref action-indexes (c-action-id action)) text-updates geometry-updates damage '())))

  ;; Background symbols lower to a fixed palette at compile time. They only alter static
  ;; QuadInstance color fields; the runtime never resolves theme names or computes styles.
  (define (background-palette name)
    (cond
      [(and (list? name) (= (length name) 4) (andmap real? name)) name]
      [else (case name
      [(dark)    '(0.025 0.040 0.070 1.0)]
      [(surface) '(0.045 0.070 0.115 1.0)]
      [(panel)   '(0.070 0.100 0.155 1.0)]
      [(header)  '(0.090 0.130 0.200 1.0)]
      [(muted)   '(0.110 0.145 0.205 1.0)]
      [(accent)  '(0.075 0.310 0.265 1.0)]
      [(danger)  '(0.270 0.065 0.085 1.0)]
      [else #f])]))
  (define (layout-color node depth)
    (define explicit-background
      (background-palette (hash-ref (c-node-props node) '#:background #f)))
    (cond
      [explicit-background explicit-background]
      [(eq? (c-node-id node) 'dashboard) '(0.025 0.040 0.070 1.0)]
      [(eq? (c-node-tag node) 'button) '(0.075 0.310 0.265 1.0)]
      [(eq? (c-node-tag node) 'progress) '(0.25 0.86 0.62 1.0)]
      [(eq? (c-node-tag node) 'scrollbar) '(0.045 0.070 0.115 1.0)]
      [(eq? (c-node-tag node) 'scrollbar-thumb) '(0.28 0.72 1.0 1.0)]
      [(eq? (c-node-tag node) 'overlay)
       (cond [(regexp-match? #rx"\\$caret$" (symbol->string (c-node-id node)))
              (list 0.45 0.92 1.0 (hash-ref (c-node-props node) '#:opacity))]
             [(regexp-match? #rx"\\$focus$" (symbol->string (c-node-id node)))
              (list 0.20 0.66 1.0 (hash-ref (c-node-props node) '#:opacity))]
             [else (list 0.95 0.30 0.38 (hash-ref (c-node-props node) '#:opacity))])]
      ;; Glyphs are rendered by the placement pipeline, so an unspecified text leaf has no
      ;; opaque quad of its own. This preserves the parent/row surface behind static text;
      ;; explicit `#:background` above remains a compiler-fixed visible surface.
      [(eq? (c-node-tag node) 'text) (list 0.0 0.0 0.0 0.0)]
      [else (define shade (+ 0.11 (* depth 0.025)))
            (list shade (+ shade 0.035) (+ shade 0.09) 1.0)]))

  (define (layout-height node)
    (case (c-node-tag node)
      [(button) 46.0]
      [(text) 28.0]
      [(progress overlay stack) 22.0]
      [(scrollbar) 96.0]
      [(scrollbar-thumb) 18.0]
      [(virtual-list) 42.0]
      [(row) 64.0]
      [else 42.0]))

  ;; 宏展开时执行的微型、受限 layout solver。它只支持本 DSL 已公开的
  ;; column/row template；不接受无界 runtime measure，因此结果可完全序列化。
  (define (compile-layout-plan root)
    (define binding-by-id
      (for/hash ([binding (in-list (collect-glyph-bindings root))])
        (values (c-binding-node-id binding) binding)))
    (define (node-layout node depth x y width)
      ;; Leaf 的字面 width/height 在宏展开期落入 Layout Plan；不得留给 host 求解。
      (define resolved-x (+ x (hash-ref (c-node-props node) '#:x 0.0)))
      (define resolved-y (+ y (hash-ref (c-node-props node) '#:y 0.0)))
      (define resolved-width (hash-ref (c-node-props node) '#:width width))
      (define resolved-height
        (if (eq? (c-node-tag node) 'virtual-list)
            (hash-ref (c-node-props node) 'viewport-height)
            (hash-ref (c-node-props node) '#:height (layout-height node))))
      (define height resolved-height)
      (define binding (hash-ref binding-by-id (c-node-id node) #f))
      (define glyph-offset (if binding (c-binding-offset binding) 0))
      (define glyph-count (if binding (c-binding-glyph-count binding) 0))
      (define atlas-page (if binding (c-binding-atlas-page binding) 0))
      (define glyph-ids (if binding (c-binding-glyph-ids binding) '()))
      (define glyph-advances (if binding (c-binding-glyph-advances binding) '()))
      (define vertex-count (if binding (* glyph-count 6) 6))
      (define current
        (c-layout (c-node-id node) (c-node-tag node) resolved-x resolved-y resolved-width height
                  (hash-ref (c-node-props node) 'elevation 0)
                  (layout-color node depth) glyph-offset glyph-count atlas-page glyph-ids glyph-advances 0 vertex-count))
      (cond
        [(eq? (c-node-tag node) 'virtual-list)
         ;; Rows have preallocated geometry regardless of visibility. The container's
         ;; compiler clip is the sole viewport boundary; scroll later selects row slots.
         (define row-height (hash-ref (c-node-props node) 'row-height))
         (define child-results
           (append-map
            (lambda (child index)
              (define-values (layouts ignored-y)
                (node-layout child (+ depth 1) resolved-x (+ resolved-y (* index row-height)) resolved-width))
              layouts)
            (c-node-children node)
            (range (length (c-node-children node)))))
         (values (cons current child-results) (+ y height 10.0))]
        [(eq? (c-node-tag node) 'stack)
          ;; A visual-anchor stack exposes its already-resolved local frame to children.
          ;; This is still expansion-time geometry; ordinary legacy stacks retain their
          ;; historical parent-frame semantics for ABI compatibility.
          (define anchored? (hash-ref (c-node-props node) '#:visual-anchor #f))
          (define child-x (if anchored? resolved-x x))
          (define child-y (if anchored? resolved-y y))
          (define child-width (if anchored? resolved-width width))
          (define child-results
            (append-map
             (lambda (child)
               (define-values (layouts ignored-y)
                 (node-layout child (+ depth 1) child-x child-y child-width))
               layouts)
             (c-node-children node)))
          (values (cons current child-results) (+ y height 10.0))]
         [(and (eq? (c-node-tag node) 'column)
               (hash-ref (c-node-props node) '#:visual-flow #f))
          ;; visual-flow is emitted only by app-shell. Its padding and gap are literals
          ;; resolved at expansion; runtime receives only the resulting layouts.
          (define padding (hash-ref (c-node-props node) '#:padding 0.0))
          (define gap (hash-ref (c-node-props node) '#:gap 0.0))
          (define-values (child-results final-y)
            (let loop ([children (c-node-children node)]
                       [next-y (+ resolved-y padding)]
                       [result '()])
              (cond
                [(null? children) (values (reverse result) next-y)]
                [else
                 (define-values (layouts child-next-y)
                   (node-layout (car children) (+ depth 1) (+ resolved-x padding) next-y
                                (- resolved-width (* 2.0 padding))))
                 (loop (cdr children) (+ child-next-y gap) (append (reverse layouts) result))])))
          (values (cons current child-results) final-y)]
        [(eq? (c-node-tag node) 'scrollbar)
         ;; Track and thumb share the compiler-resolved track origin. The thumb's local
         ;; `#:y` is initially zero; drag later patches only this known instance field.
         (define child-results
           (append-map
            (lambda (child)
              (define-values (layouts ignored-y)
                (node-layout child (+ depth 1) resolved-x resolved-y resolved-width))
              layouts)
            (c-node-children node)))
         (values (cons current child-results) (+ y height 10.0))]
        [(eq? (c-node-tag node) 'row)
         (define children (c-node-children node))
         (define child-count (max 1 (length children)))
         (define child-width (/ (- width 24.0) child-count))
         (define child-results
           (append-map
            (lambda (child index)
              (define-values (layouts ignored-y)
                (node-layout child (+ depth 1) (+ x 12.0 (* index child-width)) (+ y 18.0) (- child-width 8.0)))
              layouts)
            children
            (range child-count)))
         (values (cons current child-results) (+ y height 10.0))]
        [else
         (define-values (child-layouts final-y)
           (let loop ([children (c-node-children node)] [next-y (+ y height 10.0)] [result '()])
             (cond
               [(null? children) (values (reverse result) next-y)]
               [else
                (define-values (layouts child-next-y)
                  (node-layout (car children) (+ depth 1) (+ x 18.0) next-y (- width 36.0)))
                (loop (cdr children) child-next-y (append (reverse layouts) result))])))
         (values (cons current child-layouts) final-y)]))
    (define-values (raw-layouts ignored-y)
      (node-layout root 0 (canvas-margin) (canvas-margin)
                   (- (canvas-width) (* 2.0 (canvas-margin)))))
    ;; Offset 与 layout entry index 一一对应，后端无需根据 node tree 再寻址。
    (for/list ([layout (in-list raw-layouts)] [index (in-naturals)])
      (struct-copy c-layout layout [instance-offset (* index quad-instance-bytes)])))

  ;; Radius is a compiler-owned visual declaration. v3 admits only static stack
  ;; surfaces and buttons with an explicit positive radius; all list rows, scrollbars,
  ;; overlays, text and root clear slot remain hard rectangles.
  (define (compile-rounded-surface-plan root layouts)
    (define aa-width-px 1.0)
    (define layout-by-id
      (for/hash ([layout (in-list layouts)])
        (values (c-layout-id layout) layout)))
    (define surfaces
      (for/list ([node (in-list (walk-nodes root))]
                 #:when (let ([radius (hash-ref (c-node-props node) '#:radius #f)])
                          (and radius
                               (member (c-node-tag node) '(stack button)))))
        (define radius (hash-ref (c-node-props node) '#:radius))
        (unless (and (real? radius) (> radius 0.0))
          (raise-syntax-error 'rounded-surface-plan "#:radius must lower to a positive compile-time number" (c-node-source node)))
        (define layout (hash-ref layout-by-id (c-node-id node)
                                 (lambda () (raise-syntax-error 'rounded-surface-plan "rounded node is missing from layout plan" (c-node-source node)))))
        (define width (c-layout-width layout))
        (define height (c-layout-height layout))
        (define offset (c-layout-instance-offset layout))
        (unless (and (> width 0.0) (> height 0.0)
                     (<= radius (/ (min width height) 2.0)))
          (raise-syntax-error 'rounded-surface-plan
                              "#:radius must not exceed half of the compiler-fixed surface size"
                              (c-node-source node)))
        (unless (positive? offset)
          (raise-syntax-error 'rounded-surface-plan "root clear quad may not be a rounded surface" (c-node-source node)))
        (c-rounded-surface (c-node-id node) offset (c-layout-x layout) (c-layout-y layout)
                           width height radius aa-width-px)))
    (define sorted (sort surfaces < #:key c-rounded-surface-instance-offset))
    (unless (= (length sorted) (length (remove-duplicates (map c-rounded-surface-instance-offset sorted))))
      (raise-syntax-error 'rounded-surface-plan "rounded surfaces must own unique QuadInstance offsets" (c-node-source root)))
    sorted)

  ;; The v1 recipe is deliberately finite and symmetric: it models ambient elevation
  ;; without a runtime blur, filter, animation or directional light input. Every tuple
  ;; is `(blur-px opacity)` and becomes one immutable shadow quad.
  (define (shadow-layer-recipe elevation)
    (case elevation
      [(1) '((3.0 0.14) (7.0 0.055))]
      [(2) '((4.0 0.17) (10.0 0.070))]
      [(3) '((6.0 0.19) (14.0 0.080))]
      [(4) '((8.0 0.21) (18.0 0.090))]
      [(5) '((10.0 0.23) (22.0 0.100))]
      [else '()]))

  (define (compile-shadow-surface-plan root layouts)
    ;; Shadow v1 is a desktop chrome feature. Bench fixtures retain a literal false
    ;; plan for backwards compatibility and avoid allocating a second static pass.
    (if (not (eq? (hash-ref (current-static-visual-preset) 'id) 'desktop-wide))
        '()
        (let* ([layout-by-id (for/hash ([layout (in-list layouts)]) (values (c-layout-id layout) layout))]
               [layers
                (append-map
                 (lambda (node)
                   (define elevation (hash-ref (c-node-props node) 'elevation 0))
                   (cond
                     [(zero? elevation) '()]
                     [else
                      (unless (and (eq? (c-node-tag node) 'stack)
                                   (hash-has-key? (c-node-props node) '#:radius))
                        (raise-syntax-error 'shadow-surface-plan
                                            "positive elevation requires a static rounded stack surface"
                                            (c-node-source node)))
                      (define radius (hash-ref (c-node-props node) '#:radius))
                      (define layout
                        (hash-ref layout-by-id (c-node-id node)
                                  (lambda () (raise-syntax-error 'shadow-surface-plan
                                                                   "elevated surface is missing from layout plan"
                                                                   (c-node-source node)))))
                      (unless (and (exact-integer? elevation) (<= 1 elevation 5)
                                   (real? radius) (> radius 0.0)
                                   (> (c-layout-width layout) 0.0) (> (c-layout-height layout) 0.0)
                                   (<= radius (/ (min (c-layout-width layout) (c-layout-height layout)) 2.0)))
                        (raise-syntax-error 'shadow-surface-plan
                                            "elevation/radius/geometry violates the fixed shadow contract"
                                            (c-node-source node)))
                      (for/list ([recipe (in-list (shadow-layer-recipe elevation))] [layer (in-naturals 1)])
                        (define blur (first recipe))
                        (define opacity (second recipe))
                        (c-shadow-surface
                         (string->symbol (format "~a$shadow-~a" (c-node-id node) layer))
                         (c-node-id node) (c-layout-instance-offset layout) elevation layer
                         (- (c-layout-x layout) blur) (- (c-layout-y layout) blur)
                         (+ (c-layout-width layout) (* 2.0 blur))
                         (+ (c-layout-height layout) (* 2.0 blur))
                         radius blur opacity))]))
                 (walk-nodes root))]
               [sorted (sort layers < #:key c-shadow-surface-layer)])
          (unless (= (length layers) (length (remove-duplicates (map c-shadow-surface-id layers))))
            (raise-syntax-error 'shadow-surface-plan "shadow layer IDs must be unique" (c-node-source root)))
          ;; Canonical source/layer sort prevents source-tree traversal accidents from
          ;; changing blend order. Larger blur draws first; smaller, denser layer last.
          (sort layers
                (lambda (left right)
                  (cond [(symbol<? (c-shadow-surface-source-id left) (c-shadow-surface-source-id right)) #t]
                        [(symbol<? (c-shadow-surface-source-id right) (c-shadow-surface-source-id left)) #f]
                        [else (> (c-shadow-surface-layer left) (c-shadow-surface-layer right))]))))))

  (define (shadow-surface-plan->datum layers)
    (if (null? layers)
        '#f
        `(shadow-surface-plan
          (list ,@(for/list ([surface (in-list layers)])
                     `(shadow-surface ',(c-shadow-surface-id surface)
                                      ',(c-shadow-surface-source-id surface)
                                      ,(c-shadow-surface-source-instance-offset surface)
                                      ,(c-shadow-surface-elevation surface)
                                      ,(c-shadow-surface-layer surface)
                                      ,(c-shadow-surface-x surface)
                                      ,(c-shadow-surface-y surface)
                                      ,(c-shadow-surface-width surface)
                                      ,(c-shadow-surface-height surface)
                                      ,(c-shadow-surface-radius-px surface)
                                      ,(c-shadow-surface-blur-px surface)
                                      ,(c-shadow-surface-opacity surface)))))))

  (define (rounded-surface-plan->datum surfaces)
    (if (null? surfaces)
        '#f
        `(rounded-surface-plan 1.0
          (list ,@(for/list ([surface (in-list surfaces)])
                     `(rounded-surface ',(c-rounded-surface-id surface)
                                       ,(c-rounded-surface-instance-offset surface)
                                       ,(c-rounded-surface-x surface)
                                       ,(c-rounded-surface-y surface)
                                       ,(c-rounded-surface-width surface)
                                       ,(c-rounded-surface-height surface)
                                       ,(c-rounded-surface-radius-px surface)
                                       ,(c-rounded-surface-aa-width-px surface)))))))

  (define (compile-event-map root layouts action-indexes transaction-indexes)
    (define layout-by-id (for/hash ([layout (in-list layouts)]) (values (c-layout-id layout) layout)))
    (define buttons (filter (lambda (node) (eq? (c-node-tag node) 'button))
                            (walk-nodes root)))
    (for/list ([node (in-list buttons)]
               [slot (in-naturals)])
      ;; slot 与 z-index 使用稳定 DFS 顺序；重叠时 host 选择更大的 z-index。
      (define layout (hash-ref layout-by-id (c-node-id node)))
      (define base-pos
        (list (- (* 2.0 (/ (c-layout-x layout) (canvas-width))) 1.0)
              (- 1.0 (* 2.0 (/ (+ (c-layout-y layout) (c-layout-height layout)) (canvas-height))))))
      ;; Screen-space 向下 2 px 的NDC值由当前编译期canvas高度确定。
      (define pressed-pos (list (first base-pos) (- (second base-pos) (/ 4.0 (canvas-height)))))
      (define dispatch-id (hash-ref (c-node-props node) 'on))
      (define transaction-op (hash-ref (c-node-props node) '#:transaction-op #f))
      (define action-ids (hash-ref (c-node-props node) '#:multi-actions
                                   (if transaction-op '() (list dispatch-id))))
      (define-values (action action-index transaction-index)
        (if transaction-op
            (values #f #f
                    (hash-ref transaction-indexes dispatch-id
                              (lambda () (raise-syntax-error 'transaction-button "undeclared transaction ID" (c-node-source node)))))
            (values dispatch-id
                    (hash-ref action-indexes dispatch-id
                              (lambda () (raise-syntax-error 'button "undeclared action ID" (c-node-source node))))
                    #f)))
      (when (and (not transaction-op) (not (equal? action-ids (cons dispatch-id (cdr action-ids)))))
        (raise-syntax-error 'multi-action-event "#:on must be the first #:multi-actions member" (c-node-source node)))
      (for ([action-id (in-list action-ids)])
        (unless (hash-has-key? action-indexes action-id)
          (raise-syntax-error 'multi-action-event "multi-action event references undeclared action ID" (c-node-source node))))
      (c-event slot
                (c-node-id node)
                action action-index action-ids transaction-op transaction-index
                (c-layout-x layout) (c-layout-y layout)
               (c-layout-width layout) (c-layout-height layout)
               slot (c-layout-instance-offset layout)
               (c-layout-color layout)
               '(0.15 0.86 0.58 1.0)
               '(0.045 0.52 0.30 1.0)
               base-pos pressed-pos)))

  (define (compile-animation-tracks events)
    ;; 当前 MVP 固化每个 button 的 release 回弹轨道。曲线、持续时间与字段选择
    ;; 都是编译产物；frame clock 运行时不拥有通用 animation object graph。
    (for/list ([event (in-list events)])
      (c-animation
       (string->symbol (format "release-~a" (c-event-node-id event)))
       event 80 'ease-out)))

  (define (compile-frame-schedule events tracks plans)
    (define release-tasks
      (for/list ([track (in-list tracks)])
        (define event (c-animation-event track))
        (c-frame-task (c-animation-id track) 'release 10
                      (list (list (c-event-instance-offset event) 8)
                            (list (+ (c-event-instance-offset event) 16) 16))
                      '() 2 '())))
    (define hover-tasks
      (for/list ([event (in-list events)])
        (c-frame-task (string->symbol (format "hover-~a" (c-event-node-id event))) 'hover 20
                      (list (list (+ (c-event-instance-offset event) 16) 16))
                      '() 2 '())))
    (define pressed-tasks
      (for/list ([event (in-list events)])
        (c-frame-task (string->symbol (format "pressed-~a" (c-event-node-id event))) 'pressed 30
                      (list (list (c-event-instance-offset event) 8)
                            (list (+ (c-event-instance-offset event) 16) 16))
                      '() 2 '())))
    (define transaction-tasks
      (for/list ([event (in-list events)] #:when (c-event-transaction-op event))
        ;; 事务业务 writes 是 State/Glyph slot executor 的职责；此 task 只提供 fixed batch identity/priority/tile address。
        (c-frame-task (string->symbol (format "transaction-~a" (c-event-transaction-index event)))
                      'transaction 40 '() '() 2 '())))
    (define action-tasks
      (for/list ([plan (in-list plans)])
        ;; Action 不再整段覆写 32-byte glyph cell：每个固定 slot 只写首个 u32 glyph_id。
        ;; slot 和 offset 均来自 compiler 的 binding range，runtime 不参与寻址。
        (define text-writes
          (append-map
           (lambda (binding)
             (for/list ([index (in-range (c-binding-glyph-count binding))])
               (list (+ (c-binding-offset binding) (* index glyph-instance-bytes)) 4)))
           (c-action-plan-text-updates plan)))
        (define instance-writes
          (for/list ([binding (in-list (c-action-plan-instance-updates plan))])
            (define layout (c-instance-binding-layout binding))
            (list (+ (c-layout-instance-offset layout) 8) 4)))
        (c-frame-task (c-action-plan-id plan) 'action 40 (append text-writes instance-writes) '() 2 '())))
    (append release-tasks hover-tasks pressed-tasks transaction-tasks action-tasks))

  (define (range-overlap left right)
    (define start (max (first left) (first right)))
    (define end (min (+ (first left) (second left)) (+ (first right) (second right))))
    (and (< start end) (list start (- end start))))

  (define (task-winner left right)
    (cond [(> (c-frame-task-priority left) (c-frame-task-priority right)) (c-frame-task-id left)]
          [(< (c-frame-task-priority left) (c-frame-task-priority right)) (c-frame-task-id right)]
          [(string<? (symbol->string (c-frame-task-id left)) (symbol->string (c-frame-task-id right)))
           (c-frame-task-id left)]
          [else (c-frame-task-id right)]))

  (define (compile-conflict-graph tasks)
    (apply append
           (for*/list ([index (in-range (length tasks))]
                       [other-index (in-range (add1 index) (length tasks))])
             (define left (list-ref tasks index))
             (define right (list-ref tasks other-index))
             (define overlaps
               (filter values
                       (for*/list ([left-range (in-list (c-frame-task-writes left))]
                                   [right-range (in-list (c-frame-task-writes right))])
                         (range-overlap left-range right-range))))
             (if (null? overlaps)
                 '()
                 (list (c-conflict (c-frame-task-id left) (c-frame-task-id right)
                                   (task-winner left right) overlaps))))))

  ;; 统一的稳定执行顺序：低 priority 先、高 priority 后；同 priority 使用 ID 字典序。
  ;; winner-only lowering 已剔除被覆盖字段，这个顺序仍保留为后端可审计 batch ABI。
  (define (task-execution-before? left right)
    (or (< (c-frame-task-priority left) (c-frame-task-priority right))
        (and (= (c-frame-task-priority left) (c-frame-task-priority right))
             (string<? (symbol->string (c-frame-task-id left))
                       (symbol->string (c-frame-task-id right))))))

  (define (merge-adjacent-coalesced-writes writes)
    (foldr (lambda (write acc)
             (cond
               [(null? acc) (list write)]
               [else
                (define next (car acc))
                (if (and (eq? (c-coalesced-write-task-id write) (c-coalesced-write-task-id next))
                         (= (+ (c-coalesced-write-offset write) (c-coalesced-write-byte-length write))
                            (c-coalesced-write-offset next)))
                    (cons (c-coalesced-write (c-coalesced-write-task-id write)
                                             (c-coalesced-write-offset write)
                                             (+ (c-coalesced-write-byte-length write)
                                                (c-coalesced-write-byte-length next)))
                          (cdr acc))
                    (cons write acc))]))
           '()
           (reverse writes)))

  (define (merge-adjacent-coalesced-eliminations eliminations)
    (foldr (lambda (eliminated acc)
             (cond
               [(null? acc) (list eliminated)]
               [else
                (define next (car acc))
                (if (and (eq? (c-coalesced-elimination-task-id eliminated) (c-coalesced-elimination-task-id next))
                         (eq? (c-coalesced-elimination-winner eliminated) (c-coalesced-elimination-winner next))
                         (= (+ (c-coalesced-elimination-offset eliminated)
                               (c-coalesced-elimination-byte-length eliminated))
                            (c-coalesced-elimination-offset next)))
                    (cons (c-coalesced-elimination (c-coalesced-elimination-task-id eliminated)
                                                   (c-coalesced-elimination-offset eliminated)
                                                   (+ (c-coalesced-elimination-byte-length eliminated)
                                                      (c-coalesced-elimination-byte-length next))
                                                   (c-coalesced-elimination-winner eliminated))
                          (cdr acc))
                    (cons eliminated acc))]))
           '()
           (reverse eliminations)))

  ;; 把所有 write 起止点切成不重叠 byte segment；每个 segment 只保留 `task-winner` 的写。
  ;; 因此 partial overlap 也可被证明，而不是只能处理整字段完全覆盖。
  (define (winner-only-write-plan tasks)
    (define boundaries
      (sort (remove-duplicates
             (append-map (lambda (task)
                           (append-map (lambda (write)
                                         (list (first write) (+ (first write) (second write))))
                                       (c-frame-task-writes task)))
                         tasks))
            <))
    (define raw-winners '())
    (define raw-eliminations '())
    (for ([start (in-list boundaries)] [end (in-list (rest boundaries))])
      (when (< start end)
        (define contenders
          (filter (lambda (task)
                    (ormap (lambda (write)
                             (and (<= (first write) start)
                                  (<= end (+ (first write) (second write)))))
                           (c-frame-task-writes task)))
                  tasks))
        (unless (null? contenders)
          (define winner-task
            (for/fold ([best (car contenders)]) ([task (in-list (cdr contenders))])
              (define winner-id (task-winner best task))
              (if (eq? winner-id (c-frame-task-id best)) best task)))
          (define winner-id (c-frame-task-id winner-task))
          (set! raw-winners (cons (c-coalesced-write winner-id start (- end start)) raw-winners))
          (for ([task (in-list contenders)] #:unless (eq? (c-frame-task-id task) winner-id))
            (set! raw-eliminations
                  (cons (c-coalesced-elimination (c-frame-task-id task) start (- end start) winner-id)
                        raw-eliminations))))))
    (define ordered-tasks (sort tasks task-execution-before?))
    (define rank-by-id
      (for/hash ([task (in-list ordered-tasks)] [rank (in-naturals)])
        (values (c-frame-task-id task) rank)))
    (define (winner-write<? left right)
      (define left-rank (hash-ref rank-by-id (c-coalesced-write-task-id left)))
      (define right-rank (hash-ref rank-by-id (c-coalesced-write-task-id right)))
      (or (< left-rank right-rank)
          (and (= left-rank right-rank)
               (< (c-coalesced-write-offset left) (c-coalesced-write-offset right)))))
    (define (elimination<? left right)
      (define left-rank (hash-ref rank-by-id (c-coalesced-elimination-task-id left)))
      (define right-rank (hash-ref rank-by-id (c-coalesced-elimination-task-id right)))
      (or (< left-rank right-rank)
          (and (= left-rank right-rank)
               (< (c-coalesced-elimination-offset left) (c-coalesced-elimination-offset right)))))
    (values (sort (merge-adjacent-coalesced-writes (reverse raw-winners)) winner-write<?)
            (sort (merge-adjacent-coalesced-eliminations (reverse raw-eliminations)) elimination<?)))

  (define (compile-frame-coalesced-batches tasks events conflicts root)
    (define task-by-id (for/hash ([task (in-list tasks)]) (values (c-frame-task-id task) task)))
    (define (task id)
      (or (hash-ref task-by-id id #f)
          (raise-syntax-error 'noir (format "coalesced batch refers to unknown frame task ~a" id) (c-node-source root))))
    (define (make-batch id task-ids)
      (define batch-tasks (map task task-ids))
      (define execution-order (map c-frame-task-id (sort batch-tasks task-execution-before?)))
      (define-values (winner-writes eliminated-writes) (winner-only-write-plan batch-tasks))
      (define merged-tile-ids
        (sort (remove-duplicates (append-map c-frame-task-tile-ids batch-tasks)) <))
      (define batch-edges
        (filter (lambda (edge)
                  (and (member (c-conflict-left edge) task-ids)
                       (member (c-conflict-right edge) task-ids)))
                conflicts))
      (c-coalesced-batch id task-ids execution-order winner-writes eliminated-writes merged-tile-ids batch-edges
                          'coalesced (hash 'coalesced 0.0) (hash 'mode 'unprofiled-default)
                          #f '() '() '()))
    ;; press batch 是 hover/pressed 可能同帧时的 field coalescing；activate batch 是 release
    ;; 与业务 action 同帧的 tile/write coalescing。二者均由现有 Event Map 命名约定唯一确定。
    (define batches
      (append-map
       (lambda (event)
         (define node (c-event-node-id event))
         (define dispatch-tasks
           (if (c-event-transaction-op event)
               (list (string->symbol (format "transaction-~a" (c-event-transaction-index event))))
               (c-event-action-ids event)))
         (list
          (make-batch (string->symbol (format "coalesced-press-~a" node))
                      (list (string->symbol (format "hover-~a" node))
                            (string->symbol (format "pressed-~a" node))))
          (make-batch (string->symbol (format "coalesced-activate-~a" node))
                      (cons (string->symbol (format "release-~a" node)) dispatch-tasks))))
       events))
    (assert-frame-coalesced-batches! batches tasks conflicts root)
    batches)

  (define (assert-frame-coalesced-batches! batches tasks conflicts root)
    (define task-by-id (for/hash ([task (in-list tasks)]) (values (c-frame-task-id task) task)))
    (for ([batch (in-list batches)])
      (define task-ids (c-coalesced-batch-task-ids batch))
      (define batch-tasks (map (lambda (id) (hash-ref task-by-id id)) task-ids))
      (unless (equal? (c-coalesced-batch-execution-order batch)
                      (map c-frame-task-id (sort batch-tasks task-execution-before?)))
        (raise-syntax-error 'noir "coalesced batch execution order disagrees with task priority order" (c-node-source root)))
      (define expected-tiles (sort (remove-duplicates (append-map c-frame-task-tile-ids batch-tasks)) <))
      (unless (and (pair? expected-tiles) (equal? expected-tiles (c-coalesced-batch-merged-tile-ids batch)))
        (raise-syntax-error 'noir "coalesced batch tile IDs disagree with member task union" (c-node-source root)))
      ;; winner write 必须仍然属于 winner 的原始 writes；elimination 必须由 task-winner 证明。
      (for ([write (in-list (c-coalesced-batch-winner-writes batch))])
        (define owner (hash-ref task-by-id (c-coalesced-write-task-id write)))
        (unless (ormap (lambda (raw)
                         (and (<= (first raw) (c-coalesced-write-offset write))
                              (<= (+ (c-coalesced-write-offset write) (c-coalesced-write-byte-length write))
                                  (+ (first raw) (second raw)))))
                       (c-frame-task-writes owner))
          (raise-syntax-error 'noir "coalesced winner write escapes its source task write range" (c-node-source root))))
      (for ([eliminated (in-list (c-coalesced-batch-eliminated-writes batch))])
        (define loser (hash-ref task-by-id (c-coalesced-elimination-task-id eliminated)))
        (define winner (hash-ref task-by-id (c-coalesced-elimination-winner eliminated)))
        (unless (eq? (task-winner loser winner) (c-frame-task-id winner))
          (raise-syntax-error 'noir "eliminated coalesced write has no priority winner proof" (c-node-source root))))
      (for ([edge (in-list (c-coalesced-batch-conflict-edges batch))])
        (unless (and (member (c-conflict-left edge) task-ids) (member (c-conflict-right edge) task-ids))
          (raise-syntax-error 'noir "coalesced batch includes an external conflict edge" (c-node-source root)))))
    (void))

  (define (viewport-area) (* (canvas-width) (canvas-height)))
  (define full-redraw-threshold 0.60)

  (define (rect->tile rect)
    (c-render-tile (c-rect-x rect) (c-rect-y rect) (c-rect-width rect) (c-rect-height rect)
                   (list (c-rect-node rect)) '() '() 'none 'unselected (hash)))

  ;; 相交或边界相接的 damage rect 会合并成最小 union tile。
  (define (tiles-touch? left right)
    (and (<= (c-render-tile-x left) (+ (c-render-tile-x right) (c-render-tile-width right)))
         (<= (c-render-tile-x right) (+ (c-render-tile-x left) (c-render-tile-width left)))
         (<= (c-render-tile-y left) (+ (c-render-tile-y right) (c-render-tile-height right)))
         (<= (c-render-tile-y right) (+ (c-render-tile-y left) (c-render-tile-height left)))))

  (define (merge-tiles left right)
    (define x (min (c-render-tile-x left) (c-render-tile-x right)))
    (define y (min (c-render-tile-y left) (c-render-tile-y right)))
    (define right-edge (max (+ (c-render-tile-x left) (c-render-tile-width left))
                            (+ (c-render-tile-x right) (c-render-tile-width right))))
    (define bottom-edge (max (+ (c-render-tile-y left) (c-render-tile-height left))
                             (+ (c-render-tile-y right) (c-render-tile-height right))))
    (c-render-tile x y (- right-edge x) (- bottom-edge y)
                    (append (c-render-tile-nodes left) (c-render-tile-nodes right)) '() '() 'none 'unselected (hash)))

  (define (insert-merged-tile tile tiles)
    (define hit (findf (lambda (existing) (tiles-touch? tile existing)) tiles))
    (if hit
        (insert-merged-tile (merge-tiles tile hit) (remove hit tiles))
        (cons tile tiles)))

  (define (layout-intersects-tile? layout tile)
    (and (< (c-layout-x layout) (+ (c-render-tile-x tile) (c-render-tile-width tile)))
         (< (c-render-tile-x tile) (+ (c-layout-x layout) (c-layout-width layout)))
         (< (c-layout-y layout) (+ (c-render-tile-y tile) (c-render-tile-height tile)))
         (< (c-render-tile-y tile) (+ (c-layout-y layout) (c-layout-height layout)))))

  (struct c-composite (slot node-id z-layer clip-stack-id clip-rect blend-mode opaque? batch-key layout) #:transparent)

  (define (viewport-rect) (list 0.0 0.0 (canvas-width) (canvas-height)))
  (define fragment-budget 2)

  (define (rect-intersection left right)
    (define x (max (first left) (first right)))
    (define y (max (second left) (second right)))
    (define right-edge (min (+ (first left) (third left)) (+ (first right) (third right))))
    (define bottom-edge (min (+ (second left) (fourth left)) (+ (second right) (fourth right))))
    (and (> right-edge x) (> bottom-edge y)
         (list x y (- right-edge x) (- bottom-edge y))))

  (define (layout-rect layout)
    (list (c-layout-x layout) (c-layout-y layout) (c-layout-width layout) (c-layout-height layout)))

  (define (rect-covers? upper lower)
    (and (<= (first upper) (first lower))
         (<= (second upper) (second lower))
         (>= (+ (first upper) (third upper)) (+ (first lower) (third lower)))
         (>= (+ (second upper) (fourth upper)) (+ (second lower) (fourth lower)))))

  (define (compile-composites root layouts)
    (define layout-by-id (for/hash ([layout (in-list layouts)]) (values (c-layout-id layout) layout)))
    (define (active-clip-rect clip-stack)
      (for/fold ([rect (viewport-rect)]) ([clip-id (in-list clip-stack)])
        (or (rect-intersection rect (layout-rect (hash-ref layout-by-id clip-id)))
            (raise-syntax-error 'noir "nested clip stack has empty intersection"))))
    (define (clip-stack-id clip-stack)
      (if (null? clip-stack) 'root
          (string->symbol (string-join (map symbol->string (reverse clip-stack)) ">"))))
    (define (walk node clip-stack result)
      (define layout (hash-ref layout-by-id (c-node-id node)))
      (define own-clip? (and (member (c-node-tag node) '(stack virtual-list)) (hash-ref (c-node-props node) '#:clip #f)))
      (define child-stack (if own-clip? (cons (c-node-id node) clip-stack) clip-stack))
      (define clip-rect (active-clip-rect clip-stack))
      (define clip-id (clip-stack-id clip-stack))
      (define alpha (fourth (c-layout-color layout)))
      (define opaque? (>= alpha 1.0))
      (define blend-mode (if opaque? 'opaque 'alpha))
      (define z-layer (hash-ref (c-node-props node) '#:z 0))
      (define batch-key
        (string->symbol (format "shared-quad-atlas|clip:~a|blend:~a" clip-id blend-mode)))
      (define composite
        (c-composite (quotient (c-layout-instance-offset layout) quad-instance-bytes)
                     (c-node-id node) z-layer clip-id clip-rect blend-mode opaque? batch-key layout))
      (foldl (lambda (child acc) (walk child child-stack acc))
             (cons composite result)
             (c-node-children node)))
    (walk root '() '()))

  ;; Glyph Placement 复用 Layout Plan 的 NDC rect 以及 Composite 的 clip/z 语义。
  ;; 结果中的每个 slot 都与 glyph storage 的一个 32-byte cell 一一对应；因此 host
  ;; 不需要从 string、glyph_count 或 parent layout 重新推导位置、UV 或 buffer 地址。
  (define (compile-glyph-placement-plan root states layouts state-indexes)
    (define bindings (collect-glyph-bindings root))
    (define binding-by-id
      (for/hash ([binding (in-list bindings)])
        (values (c-binding-node-id binding) binding)))
    (define layout-by-id
      (for/hash ([layout (in-list layouts)])
        (values (c-layout-id layout) layout)))
    (define node-by-id
      (for/hash ([node (in-list (walk-nodes root))])
        (values (c-node-id node) node)))
    (define initial-state-by-id
      (for/hash ([state (in-list states)])
        (values (c-state-id state) (c-state-initial state))))
    (define composite-by-id
      (for/hash ([composite (in-list (compile-composites root layouts))])
        (values (c-composite-node-id composite) composite)))
    (define (layout-ndc-pos layout)
        (list (- (* 2.0 (/ (c-layout-x layout) (canvas-width))) 1.0)
              (- 1.0 (* 2.0 (/ (+ (c-layout-y layout) (c-layout-height layout)) (canvas-height))))))
    (define (layout-ndc-size layout)
      (list (* 2.0 (/ (c-layout-width layout) (canvas-width)))
            (* 2.0 (/ (c-layout-height layout) (canvas-height)))))
    (define font-assets-by-face
      (for/hash ([asset (in-list (current-static-font-assets))])
        (values (c-font-asset-plan-face-id asset) asset)))
    (define dynamic-cell-asset (current-static-dynamic-font-cell-asset))
    (define dynamic-cell-node-ids
      (if dynamic-cell-asset
          (dynamic-font-cell-text-node-ids root (c-dynamic-font-cell-asset-face-id dynamic-cell-asset))
          (set)))
    (define dynamic-cell-glyph-by-codepoint
      (if dynamic-cell-asset
          (for/hash ([glyph (in-list (c-dynamic-font-cell-asset-glyphs dynamic-cell-asset))])
            (values (c-font-glyph-codepoint glyph) glyph))
          (hash)))
    (define (fontc-glyph binding glyph-id)
      (define face-id (c-binding-face-id binding))
      (and face-id
           (let* ([asset (hash-ref font-assets-by-face face-id
                                   (lambda () (raise-syntax-error 'text "selected font face disappeared during lowering" (c-node-source root))))]
                  [glyph-index (bitwise-and glyph-id #xffff)])
             (unless (and (= (c-binding-atlas-page binding) (c-font-asset-plan-atlas-page asset))
                          (< glyph-index (length (c-font-asset-plan-glyphs asset))))
               (raise-syntax-error 'text "fontc glyph ID is outside the proved face domain" (c-node-source root)))
             (list-ref (c-font-asset-plan-glyphs asset) glyph-index))))
    (define (atlas-uv binding glyph-id)
      (define font-glyph (fontc-glyph binding glyph-id))
      (if font-glyph
          (let ([asset (hash-ref font-assets-by-face (c-binding-face-id binding))])
            (list (/ (exact->inexact (c-font-glyph-x font-glyph)) (c-font-asset-plan-atlas-width asset))
                  (/ (exact->inexact (c-font-glyph-y font-glyph)) (c-font-asset-plan-atlas-height asset))
                  (/ (exact->inexact (c-font-glyph-width font-glyph)) (c-font-asset-plan-atlas-width asset))
                  (/ (exact->inexact (c-font-glyph-height font-glyph)) (c-font-asset-plan-atlas-height asset))))
          (let ([glyph-index (bitwise-and glyph-id #xffff)])
            ;; 单个 legacy cell 的可采样 3×5 bitmap 永远位于 6×8 cell 的 (1,1) padding 后。
            (list (/ (+ (* glyph-index 6.0) 1.0) 162.0)
                  (/ 1.0 8.0)
                  (/ 5.0 162.0)
                  (/ 7.0 8.0)))))
    (define placements
      (append-map
       (lambda (binding)
         (define node-id (c-binding-node-id binding))
         (define node (hash-ref node-by-id node-id))
         (define layout (hash-ref layout-by-id node-id))
         (define composite (hash-ref composite-by-id node-id))
         (define state-id (c-binding-state binding))
         (define dynamic-tabular?
           (and dynamic-cell-asset (c-binding-mutable? binding)
                (not state-id) (set-member? dynamic-cell-node-ids node-id)))
         (define glyph-ids
           (cond [dynamic-tabular?
                  (for/list ([ch (in-string (hash-ref (c-node-props node) 'value))])
                    (define glyph (hash-ref dynamic-cell-glyph-by-codepoint (char->integer ch)
                                            (lambda ()
                                              (raise-syntax-error 'data-register-table
                                                                  "dynamic tabular row contains a glyph outside TABULAR_BODY_V1"
                                                                  (c-node-source node)))))
                    (encode-glyph 3 (c-font-glyph-glyph-id glyph)))]
                 [state-id
                  (if (eq? (hash-ref (c-node-props node) 'charset 'digits) 'ascii-upper)
                      (c-binding-glyph-ids binding)
                      (shape-initial-digits 'text state-id
                                            (hash-ref initial-state-by-id state-id)
                                            (c-binding-glyph-count binding)
                                            (c-node-source node)))]
                 [else (c-binding-glyph-ids binding)]))
         (define advances (if dynamic-tabular? (make-list (length glyph-ids) 10.0)
                              (c-binding-glyph-advances binding)))
         (define effective-atlas-page (if dynamic-tabular? 3 (c-binding-atlas-page binding)))
         (define effective-face-id (if dynamic-tabular? (c-dynamic-font-cell-asset-face-id dynamic-cell-asset)
                                      (c-binding-face-id binding)))
         ;; font-scale is a static page-2 typography transform. It never changes UV,
         ;; glyph IDs, storage addresses, packet membership, or the 48-byte GPU ABI.
         (define font-scale (hash-ref (c-node-props node) '#:font-scale 1.0))
         (when (and (not (= font-scale 1.0)) (or dynamic-tabular? state-id (not effective-face-id)))
           (raise-syntax-error 'text "scaled typography requires a static page-2 fontc placement" (c-node-source node)))
         (unless (= (length glyph-ids) (length advances))
           (raise-syntax-error 'text "glyph IDs and advance plan have different lengths" (c-node-source node)))
         (define total-advance (apply + advances))
         (unless (> total-advance 0.0)
           (raise-syntax-error 'text "glyph advance sum must be positive" (c-node-source node)))
         (define run-pos (layout-ndc-pos layout))
         (define run-size (layout-ndc-size layout))
         ;; Side inset is a compiler-owned typography geometry token. It is resolved once
         ;; into placement NDC; the host never measures or aligns text.
         (define text-inset (hash-ref (c-node-props node) '#:text-inset 0.12))
         (define text-run-width (* (first run-size) (- 1.0 (* 2.0 text-inset))))
         (define unit-advance (/ text-run-width total-advance))
         (define glyph-height (* (second run-size) 0.72))
         (define start-x (+ (first run-pos) (* (first run-size) text-inset)))
         (define batch-key
           (string->symbol
                    (format "glyph-atlas|page:~a|clip:~a|blend:alpha"
                    effective-atlas-page
                    (c-composite-clip-stack-id composite))))
         (let loop ([ids glyph-ids] [advance-list advances] [glyph-index 0]
                    [prefix 0.0] [result '()])
           (cond
             [(null? ids) (reverse result)]
             [else
              (define glyph-id (car ids))
              (define advance (car advance-list))
              (define glyph-byte-offset (+ (c-binding-offset binding)
                                           (* glyph-index glyph-instance-bytes)))
              (define font-glyph (fontc-glyph binding glyph-id))
              (define-values (glyph-pos glyph-size)
                (cond
                  [dynamic-tabular?
                   ;; PAGE-3 is a true fixed-cell font: prefix/advance are manifest pixels,
                   ;; converted directly to NDC once. The row may be wide, but glyphs never
                   ;; stretch to fill it and the runtime never measures the string.
                   (define px-x-scale (/ 2.0 (canvas-width)))
                   (define px-y-scale (/ 2.0 (canvas-height)))
                   (values (list (+ (first run-pos) (* 16.0 px-x-scale) (* prefix px-x-scale))
                                 (+ (second run-pos) (* (second run-size) 0.25)))
                           (list (* 10.0 px-x-scale) (* 16.0 px-y-scale)))]
                  [font-glyph
                   (let* ([asset (hash-ref font-assets-by-face (c-binding-face-id binding))]
                          ;; line scale is compile-time typography geometry: 72% of the text
                          ;; run is reserved for the manifest line box, with a fixed lower inset.
                          [line-scale (* font-scale
                                         (/ (* (second run-size) 0.72)
                                            (c-font-asset-plan-line-height asset)))]
                          ;; The run anchor is a shared lower-left NDC reference. fontc stores
                          ;; Pillow's `bearing_y = -bbox.top`, while this shader interprets `pos`
                          ;; as the glyph quad's lower-left corner. Therefore the glyph lower edge
                          ;; is offset by `bbox.bottom = height - bearing_y`, exactly once. Earlier
                          ;; variants either cancelled bearing (equal top edges) or omitted height
                          ;; (moving whole glyphs above the line).
                          [line-anchor-y (+ (second run-pos)
                                            (* (second run-size) 0.14)
                                            (* line-scale (- (c-font-asset-plan-line-height asset)
                                                             (c-font-asset-plan-pixel-size asset))))]
                          [x (+ start-x (* prefix line-scale) (* (c-font-glyph-bearing-x font-glyph) line-scale))]
                          [y (- line-anchor-y
                                (* (- (c-font-glyph-height font-glyph)
                                      (c-font-glyph-bearing-y font-glyph))
                                   line-scale))])
                     (values (list x y)
                             (list (* (c-font-glyph-width font-glyph) line-scale)
                                   (* (c-font-glyph-height font-glyph) line-scale))))]
                  [else
                   (values (list (+ start-x (* prefix unit-advance))
                                 (+ (second run-pos) (* (second run-size) 0.19)))
                           (list (* unit-advance advance 0.76) glyph-height))]))
              (define slot (quotient glyph-byte-offset glyph-instance-bytes))
              (loop (cdr ids) (cdr advance-list) (add1 glyph-index) (+ prefix advance)
                    (cons (c-glyph-placement
                           slot node-id glyph-index glyph-id effective-atlas-page
                           glyph-byte-offset (quotient glyph-byte-offset 4)
                           glyph-pos glyph-size
                           (if dynamic-tabular?
                               (let* ([glyph-index (bitwise-and glyph-id #xffff)]
                                      [glyph (list-ref (c-dynamic-font-cell-asset-glyphs dynamic-cell-asset) glyph-index)])
                                 (list (/ (exact->inexact (c-font-glyph-x glyph)) (c-dynamic-font-cell-asset-atlas-width dynamic-cell-asset))
                                       (/ (exact->inexact (c-font-glyph-y glyph)) (c-dynamic-font-cell-asset-atlas-height dynamic-cell-asset))
                                       (/ (exact->inexact (c-font-glyph-width glyph)) (c-dynamic-font-cell-asset-atlas-width dynamic-cell-asset))
                                       (/ (exact->inexact (c-font-glyph-height glyph)) (c-dynamic-font-cell-asset-atlas-height dynamic-cell-asset))))
                               (atlas-uv binding glyph-id))
                           advance
                            (c-binding-mutable? binding) state-id (and state-id (hash-ref state-indexes state-id))
                           (c-composite-clip-stack-id composite)
                           (c-composite-clip-rect composite)
                           (c-composite-z-layer composite)
                           batch-key effective-face-id)
                          result))])))
       bindings))
    (define (packet-compatible? left right)
      (and (= (c-glyph-placement-slot right) (add1 (c-glyph-placement-slot left)))
           (= (c-glyph-placement-atlas-page left) (c-glyph-placement-atlas-page right))
           (eq? (c-glyph-placement-clip-stack-id left) (c-glyph-placement-clip-stack-id right))
           (equal? (c-glyph-placement-clip-rect left) (c-glyph-placement-clip-rect right))
           (= (c-glyph-placement-z-layer left) (c-glyph-placement-z-layer right))
           (eq? (c-glyph-placement-batch-key left) (c-glyph-placement-batch-key right))
           (equal? (c-glyph-placement-dynamic? left) (c-glyph-placement-dynamic? right))))
    ;; Placement 的pos是NDC左下角；恢复为当前编译期canvas的screen rect。
    ;; bounds 是glyph geometry union与既有clip rect交集，绝不使用text run粗略layout rect。
    (define (glyph-placement-screen-rect placement)
      (define pos (c-glyph-placement-ndc-pos placement))
      (define size (c-glyph-placement-ndc-size placement))
      (define half-width (/ (canvas-width) 2.0))
      (define half-height (/ (canvas-height) 2.0))
      (list (* (+ (first pos) 1.0) half-width)
            (* (- 1.0 (+ (second pos) (second size))) half-height)
            (* (first size) half-width)
            (* (second size) half-height)))
    (define (rect-union rects)
      (define x (apply min (map first rects)))
      (define y (apply min (map second rects)))
      (define right (apply max (map (lambda (rect) (+ (first rect) (third rect))) rects)))
      (define bottom (apply max (map (lambda (rect) (+ (second rect) (fourth rect))) rects)))
      (list x y (- right x) (- bottom y)))
    (define (finish-packet first previous reverse-nodes reverse-placements acc)
      (define placement-count (add1 (- (c-glyph-placement-slot previous)
                                       (c-glyph-placement-slot first))))
      (define nodes (remove-duplicates (reverse reverse-nodes)))
      (define bounds
        (or (rect-intersection (rect-union (map glyph-placement-screen-rect (reverse reverse-placements)))
                              (c-glyph-placement-clip-rect first))
            (raise-syntax-error 'text "glyph packet is fully clipped at compile time" (c-node-source root))))
      (define packet-id
        (string->symbol
         (format "glyph-packet-page~a-slot~a-~a"
                 (c-glyph-placement-atlas-page first)
                 (c-glyph-placement-slot first)
                 (c-glyph-placement-slot previous))))
      (cons (c-glyph-packet packet-id
                             (c-glyph-placement-atlas-page first)
                             (c-glyph-placement-slot first)
                             placement-count
                             (c-glyph-placement-glyph-byte-offset first)
                             (* placement-count glyph-instance-bytes)
                             nodes bounds
                             (c-glyph-placement-clip-stack-id first)
                             (c-glyph-placement-clip-rect first)
                             (c-glyph-placement-z-layer first)
                             (c-glyph-placement-batch-key first)
                             (c-glyph-placement-dynamic? first))
            acc))
    (define packets
      (let loop ([remaining placements] [first #f] [previous #f] [reverse-nodes '()] [reverse-placements '()] [acc '()])
        (cond
          [(null? remaining)
           (if first (reverse (finish-packet first previous reverse-nodes reverse-placements acc)) (reverse acc))]
          [(not first)
           (loop (cdr remaining) (car remaining) (car remaining)
                 (list (c-glyph-placement-node-id (car remaining))) (list (car remaining)) acc)]
          [(packet-compatible? previous (car remaining))
           (loop (cdr remaining) first (car remaining)
                 (cons (c-glyph-placement-node-id (car remaining)) reverse-nodes)
                 (cons (car remaining) reverse-placements) acc)]
          [else
           (loop (cdr remaining) (car remaining) (car remaining)
                 (list (c-glyph-placement-node-id (car remaining))) (list (car remaining))
                 (finish-packet first previous reverse-nodes reverse-placements acc))])))
    (assert-glyph-placement-plan! placements packets root)
    (values placements packets))

  ;; Canonical width-32 packet plan. Each emitted lane maps directly to a dense placement slot;
  ;; shorter tail packets carry a fixed active mask and never rely on runtime bounds discovery.
  (define (compile-packet-worklists subgroup-packets)
    (define all-indices (map c-subgroup-packet-index subgroup-packets))
    (define dynamic-indices (for/list ([packet (in-list subgroup-packets)] #:when (c-subgroup-packet-dynamic? packet))
                              (c-subgroup-packet-index packet)))
    (define lists (list (c-packet-worklist 0 'all-packets all-indices)
                        (c-packet-worklist 1 'dynamic-packets dynamic-indices)
                        (c-packet-worklist 2 'no-packets '())))
    (unless (and (equal? all-indices (build-list (length subgroup-packets) values))
                 (= (length dynamic-indices) (length (remove-duplicates dynamic-indices)))
                 (andmap (lambda (index) (member index all-indices)) dynamic-indices))
      (raise-syntax-error 'text "packet worklist dependency proof failed" #f))
    lists)

  (define (compile-task-packet-worklists base subgroup-packets glyph-packets focus-graph transaction-plans)
    (define (field-indices node-id)
      (sort (remove-duplicates
             (for/list ([packet (in-list subgroup-packets)]
                        #:when (and (c-subgroup-packet-dynamic? packet)
                                    (member node-id (c-glyph-packet-nodes
                                                     (list-ref glyph-packets (c-subgroup-packet-packet-index packet))))))
               (c-subgroup-packet-index packet))) <))
    (define field-lists
      (for/list ([entry (in-list (c-focus-graph-entries focus-graph))])
        (cons (string->symbol (format "field-~a" (c-focus-entry-node-id entry)))
              (field-indices (c-focus-entry-node-id entry)))))
    (define slot->indices
      (for/hash ([entry (in-list (c-focus-graph-entries focus-graph))])
        (values (c-focus-entry-slot entry) (field-indices (c-focus-entry-node-id entry)))))
    (define transaction-lists
      (for/list ([plan (in-list transaction-plans)])
        (cons (string->symbol (format "transaction-~a" (c-transaction-plan-id plan)))
              (sort (remove-duplicates (append-map (lambda (slot) (hash-ref slot->indices slot '()))
                                                    (c-transaction-plan-field-slots plan))) <))))
    (define specs (append field-lists transaction-lists))
    (append base
            (for/list ([spec (in-list specs)] [index (in-naturals (length base))])
              (c-packet-worklist index (car spec) (cdr spec)))))

  ;; Frame Task 的 activity dispatch 地址在 macro expansion 期固定；普通 instance-only task
  ;; 绝不在运行时探测 glyph dependency，而是显式指向 no-packets。
  (define (annotate-frame-task-worklists tasks worklists focus-graph transaction-plans)
    (define no-packets-index
      (c-packet-worklist-index
       (or (findf (lambda (worklist) (eq? (c-packet-worklist-id worklist) 'no-packets)) worklists)
           (raise-syntax-error 'text "missing no-packets worklist" #f))))
    (define worklist-index-by-id
      (for/hash ([worklist (in-list worklists)])
        (values (c-packet-worklist-id worklist) (c-packet-worklist-index worklist))))
    (define field-slot-worklists
      (for/hash ([entry (in-list (c-focus-graph-entries focus-graph))])
        (values (c-focus-entry-slot entry)
                (hash-ref worklist-index-by-id
                          (string->symbol (format "field-~a" (c-focus-entry-node-id entry)))))))
    (define transaction-task-worklists
      (for/hash ([plan (in-list transaction-plans)] [index (in-naturals)])
        (values (string->symbol (format "transaction-~a" index))
                (hash-ref worklist-index-by-id
                          (string->symbol (format "transaction-~a" (c-transaction-plan-id plan)))))))
    (define transaction-task-member-worklists
      (for/hash ([plan (in-list transaction-plans)] [index (in-naturals)])
        (values (string->symbol (format "transaction-~a" index))
                (sort (remove-duplicates
                       (map (lambda (slot) (hash-ref field-slot-worklists slot))
                            (c-transaction-plan-field-slots plan)))
                      <))))
    (for/list ([task (in-list tasks)])
      (define transaction? (eq? (c-frame-task-kind task) 'transaction))
      (struct-copy c-frame-task task
                   [packet-worklist-index
                    (if transaction?
                        (hash-ref transaction-task-worklists (c-frame-task-id task))
                        no-packets-index)]
                   [packet-worklist-indices
                    (if transaction?
                        (hash-ref transaction-task-member-worklists (c-frame-task-id task))
                        '())])))

  ;; A composite worklist is a compiler-only packet union for one coalesced batch.
  ;; It is emitted only when a batch depends on more than one distinct non-empty
  ;; local list; otherwise the original single slot (or no-packets) remains optimal.
  (define (compile-composite-batch-worklists batches tasks worklists focus-graph root)
    (define task-by-id
      (for/hash ([task (in-list tasks)])
        (values (c-frame-task-id task) task)))
    (define worklist-by-index
      (for/hash ([worklist (in-list worklists)])
        (values (c-packet-worklist-index worklist) worklist)))
    (define no-packets-index
      (c-packet-worklist-index
       (or (findf (lambda (worklist) (eq? (c-packet-worklist-id worklist) 'no-packets)) worklists)
           (raise-syntax-error 'noir "missing no-packets worklist for composite lowering" (c-node-source root)))))
    (define (task-local-worklist-indices task)
      (define explicit (c-frame-task-packet-worklist-indices task))
      (if (pair? explicit) explicit (list (c-frame-task-packet-worklist-index task))))
    (define (member-indices batch)
      (sort (remove-duplicates
             (filter (lambda (index)
                       (not (null? (c-packet-worklist-packet-indices (hash-ref worklist-by-index index)))) )
                     (append-map (lambda (task-id)
                                   (task-local-worklist-indices (hash-ref task-by-id task-id)))
                                 (c-coalesced-batch-task-ids batch))))
            <))
    (define specs
      (for/list ([batch (in-list batches)])
        (define members (member-indices batch))
        (define packets
          (sort (remove-duplicates
                 (append-map (lambda (index)
                               (c-packet-worklist-packet-indices (hash-ref worklist-by-index index)))
                             members))
                <))
        (list batch members packets)))
    (define composite-specs
      (filter (lambda (spec) (> (length (second spec)) 1)) specs))
    (define composite-index-by-id
      (for/hash ([spec (in-list composite-specs)] [index (in-naturals (length worklists))])
        (values (c-coalesced-batch-id (first spec)) index)))
    (define extended-worklists
      (append worklists
              (for/list ([spec (in-list composite-specs)] [index (in-naturals (length worklists))])
                (c-packet-worklist index
                                   (string->symbol (format "batch-~a" (c-coalesced-batch-id (first spec))))
                                   (third spec)))))
    (define annotated-batches
      (for/list ([spec (in-list specs)])
        (define batch (first spec))
        (define members (second spec))
        (define packets (third spec))
        (define selected-index
          (cond [(null? members) no-packets-index]
                [(null? (cdr members)) (car members)]
                [else (hash-ref composite-index-by-id (c-coalesced-batch-id batch))]))
        (struct-copy c-coalesced-batch batch
                     [composite-worklist-index selected-index]
                     [composite-worklist-member-indices members]
                     [composite-worklist-packet-indices packets])))
    ;; The baseline keeps one request per local slot. Field tiles are compiler-known;
    ;; any batch-only tile (the trigger button) is assigned once to the first request,
    ;; so its tile union exactly equals the fused request without duplicate draws.
    (define field-slot-tiles
      (for/hash ([entry (in-list (c-focus-graph-entries focus-graph))])
        (values (c-focus-entry-slot entry) (c-focus-entry-tile-ids entry))))
    (define fused-batches
      (for/list ([batch (in-list annotated-batches)])
        (define members (c-coalesced-batch-composite-worklist-member-indices batch))
        (define baseline
          (if (<= (length members) 1)
              '()
              (let* ([member-tiles
                      (for/list ([slot (in-list members)])
                        (cons slot (hash-ref field-slot-tiles
                                             (- slot 3)
                                             (lambda () (raise-syntax-error 'noir "composite baseline slot has no compiler field tile" (c-node-source root))))))]
                     [covered (sort (remove-duplicates (append-map cdr member-tiles)) <)]
                     [residual (filter (lambda (tile) (not (member tile covered)))
                                       (c-coalesced-batch-merged-tile-ids batch))])
                (for/list ([entry (in-list member-tiles)] [rank (in-naturals)])
                  (list (car entry)
                        (sort (remove-duplicates
                               (append (cdr entry) (if (zero? rank) residual '()))) <))))))
        (struct-copy c-coalesced-batch batch [fusion-baseline-requests baseline])))
    ;; Exactness proof: the emitted selected list must be precisely the canonical
    ;; union of member local lists, and the baseline tile partition must equal the
    ;; batch tile union with no duplicate tile submission.
    (for ([batch (in-list fused-batches)])
      (define members (c-coalesced-batch-composite-worklist-member-indices batch))
      (define expected
        (sort (remove-duplicates
               (append-map (lambda (index)
                             (c-packet-worklist-packet-indices (hash-ref worklist-by-index index)))
                           members))
              <))
      (define selected
        (or (findf (lambda (worklist)
                     (= (c-packet-worklist-index worklist)
                        (c-coalesced-batch-composite-worklist-index batch)))
                   extended-worklists)
            (raise-syntax-error 'noir "composite batch selected an unknown packet worklist" (c-node-source root))))
      (define baseline (c-coalesced-batch-fusion-baseline-requests batch))
      (define baseline-tiles (append-map second baseline))
      (unless (and (equal? expected (c-coalesced-batch-composite-worklist-packet-indices batch))
                   (equal? expected (c-packet-worklist-packet-indices selected))
                   (or (<= (length members) 1)
                       (regexp-match? #rx"^batch-" (symbol->string (c-packet-worklist-id selected))))
                   (or (<= (length members) 1)
                       (and (= (length baseline) (length members))
                            (= (length baseline-tiles) (length (remove-duplicates baseline-tiles)))
                            (equal? (sort baseline-tiles <) (c-coalesced-batch-merged-tile-ids batch)))))
        (raise-syntax-error 'noir "composite packet worklist/baseline is not an exact compiler-proved union" (c-node-source root))))
    (values extended-worklists fused-batches))

  (define (compile-packet-activity-contract subgroup-packets)
    (define contract (c-packet-activity-contract (length subgroup-packets) 32 'packet_activity 'packet_activity_subgroup #t))
    (unless (and (positive? (c-packet-activity-contract-workgroup-size contract))
                 (= (c-packet-activity-contract-workgroup-size contract) 32)
                 (= (c-packet-activity-contract-packet-count contract) (length subgroup-packets))
                 (c-packet-activity-contract-differential-required? contract))
      (raise-syntax-error 'text "packet activity variant contract proof failed" #f))
    contract)

  (define (compile-subgroup-packet-plan glyph-packets)
    (define subgroup-width 32)
    (define plan
      (append-map
       (lambda (packet)
         (define first (c-glyph-packet-first-placement packet))
         (define count (c-glyph-packet-placement-count packet))
         (for/list ([local-first (in-range 0 count subgroup-width)])
           (define lanes (min subgroup-width (- count local-first)))
           (c-subgroup-packet #f (c-glyph-packet-id packet) #f (+ first local-first)
                              lanes subgroup-width (sub1 (arithmetic-shift 1 lanes)) #f #f
                              (c-glyph-packet-dynamic? packet))))
       glyph-packets))
    (define indexed
      (for/list ([packet (in-list plan)] [index (in-naturals)])
        (define packet-index
          (for/first ([source (in-list glyph-packets)] [source-index (in-naturals)]
                      #:when (eq? (c-glyph-packet-id source) (c-subgroup-packet-packet-id packet)))
            source-index))
        (c-subgroup-packet index (c-subgroup-packet-packet-id packet) packet-index
                           (c-subgroup-packet-first-placement packet)
                           (c-subgroup-packet-lane-count packet)
                           subgroup-width (c-subgroup-packet-active-lane-mask packet)
                           index (* index 16) (c-subgroup-packet-dynamic? packet))))
    (for ([packet (in-list indexed)])
      (unless (and (positive? (c-subgroup-packet-lane-count packet))
                   (<= (c-subgroup-packet-lane-count packet) subgroup-width)
                   (= (c-subgroup-packet-active-lane-mask packet)
                      (sub1 (arithmetic-shift 1 (c-subgroup-packet-lane-count packet))))
                   (= (c-subgroup-packet-activity-word-offset packet) (c-subgroup-packet-index packet))
                   (= (c-subgroup-packet-indirect-byte-offset packet) (* 16 (c-subgroup-packet-index packet))))
        (raise-syntax-error 'text "Subgroup Packet lane mask/count proof failed" #f)))
    indexed)

  ;; 宏展开期验证将 placement 的内存 ABI、page 编码、packet 覆盖和连续性固定为证据。
  (define (assert-glyph-placement-plan! placements packets root)
    (for ([placement (in-list placements)] [slot (in-naturals)])
      (unless (= (c-glyph-placement-slot placement) slot)
        (raise-syntax-error 'text "glyph placement slots must be dense and ordered" (c-node-source root)))
      (unless (= (c-glyph-placement-glyph-byte-offset placement)
                 (* slot glyph-instance-bytes))
        (raise-syntax-error 'text "glyph placement byte offset disagrees with its slot" (c-node-source root)))
      (unless (= (c-glyph-placement-glyph-word-offset placement)
                 (quotient (c-glyph-placement-glyph-byte-offset placement) 4))
        (raise-syntax-error 'text "glyph placement word offset disagrees with its byte offset" (c-node-source root)))
      (unless (= (arithmetic-shift (c-glyph-placement-glyph-id placement) -16)
                 (c-glyph-placement-atlas-page placement))
        (raise-syntax-error 'text "glyph ID page bits disagree with the atlas page" (c-node-source root))))
    (let loop ([remaining packets] [expected-slot 0])
      (unless (null? remaining)
        (define packet (car remaining))
        (unless (= (c-glyph-packet-first-placement packet) expected-slot)
          (raise-syntax-error 'text "glyph packets must cover placements in dense order" (c-node-source root)))
        (unless (= (c-glyph-packet-first-glyph-byte-offset packet)
                   (* expected-slot glyph-instance-bytes))
          (raise-syntax-error 'text "glyph packet byte offset disagrees with its first placement" (c-node-source root)))
        (unless (= (c-glyph-packet-glyph-byte-length packet)
                   (* (c-glyph-packet-placement-count packet) glyph-instance-bytes))
          (raise-syntax-error 'text "glyph packet byte length is not cell-aligned" (c-node-source root)))
        (loop (cdr remaining) (+ expected-slot (c-glyph-packet-placement-count packet)))))
    )

  (define (same-batch? left right)
    (and (= (c-composite-z-layer left) (c-composite-z-layer right))
         (eq? (c-composite-clip-stack-id left) (c-composite-clip-stack-id right))
         (eq? (c-composite-blend-mode left) (c-composite-blend-mode right))
         (eq? (c-composite-batch-key left) (c-composite-batch-key right))
         (= (c-composite-slot right) (add1 (c-composite-slot left)))))

  (define (compress-composite-ranges composites)
    (define (finish first previous acc)
      (cons (c-draw-range (c-composite-slot first)
                           (add1 (- (c-composite-slot previous) (c-composite-slot first)))
                           18
                           (c-composite-batch-key first)
                           (c-composite-z-layer first)
                           (c-composite-clip-stack-id first)
                           (c-composite-clip-rect first)
                           (c-composite-blend-mode first)
                           (c-composite-opaque? first)) acc))
    (let loop ([remaining composites] [first #f] [previous #f] [acc '()])
      (cond
        [(null? remaining) (if first (reverse (finish first previous acc)) (reverse acc))]
        [(not first) (loop (cdr remaining) (car remaining) (car remaining) acc)]
        [(same-batch? previous (car remaining)) (loop (cdr remaining) first (car remaining) acc)]
        [else (loop (cdr remaining) (car remaining) (car remaining) (finish first previous acc))])))

  (define (composite-effective-rect composite)
    (rect-intersection (layout-rect (c-composite-layout composite))
                       (c-composite-clip-rect composite)))

  (define (opaque-covers? upper lower)
    (define upper-rect (composite-effective-rect upper))
    (define lower-rect (composite-effective-rect lower))
    (and upper-rect lower-rect
         (c-composite-opaque? upper)
         (> (c-composite-z-layer upper) (c-composite-z-layer lower))
         (rect-covers? upper-rect lower-rect)))

  (define (rect-difference base cutter)
    ;; 返回 base 去除 cutter∩base 后的至多四个 axis-aligned 可见 fragment。
    (define hit (rect-intersection base cutter))
    (if (not hit)
        (list base)
        (let* ([x (first base)] [y (second base)] [w (third base)] [h (fourth base)]
               [ix (first hit)] [iy (second hit)] [iw (third hit)] [ih (fourth hit)]
               [right (+ x w)] [bottom (+ y h)] [iright (+ ix iw)] [ibottom (+ iy ih)])
          (filter (lambda (rect) (and (> (third rect) 0.0) (> (fourth rect) 0.0)))
                  (list (list x y w (- iy y))
                        (list x ibottom w (- bottom ibottom))
                        (list x iy (- ix x) ih)
                        (list iright iy (- right iright) ih))))))

  (define (partition-composite candidate visible)
    (define base (composite-effective-rect candidate))
    (define occluders
      (filter (lambda (upper)
                (define upper-rect (composite-effective-rect upper))
                (and base upper-rect
                     (c-composite-opaque? upper)
                     (> (c-composite-z-layer upper) (c-composite-z-layer candidate))
                     (rect-intersection upper-rect base)))
              visible))
    (define fragments
      (foldl (lambda (upper remaining)
               (append-map (lambda (fragment)
                             (rect-difference fragment (composite-effective-rect upper)))
                           remaining))
             (if base (list base) '())
             occluders))
    (define partitioned
      (for/list ([fragment (in-list fragments)] [index (in-naturals)])
        (define fragment-id
          (string->symbol (format "~a|fragment:~a" (c-composite-clip-stack-id candidate) index)))
        (define fragment-batch
          (string->symbol (format "shared-quad-atlas|clip:~a|blend:~a"
                                  fragment-id (c-composite-blend-mode candidate))))
        (struct-copy c-composite candidate [clip-stack-id fragment-id] [clip-rect fragment] [batch-key fragment-batch])))
    ;; 此处仅生成候选 fragment；是否采用由 tile-level Cost Model 决定。
    (c-partition partitioned
                 (if (> (length partitioned) fragment-budget)
                     'fragment-budget-exceeded
                     'none)))

  (define (coverage-partition composites)
    ;; alpha 永不进入 occluders；被完全覆盖的节点自然得到空 fragment list。
    (define partitions (map (lambda (candidate) (partition-composite candidate composites)) composites))
    (values (append-map c-partition-composites partitions)
            (ormap (lambda (partition) (eq? (c-partition-fallback-reason partition) 'fragment-budget-exceeded))
                   partitions)))

  (define (composite-area composite)
    (define rect (c-composite-clip-rect composite))
    (* (third rect) (fourth rect)))

  ;; 所有权重来自冻结 profile：draw submission、覆盖像素、clip switch 与 full tile 面积。
  ;; 宏展开后只保留数值，不把任何 profile 查询或设备自适应留给 runtime。
  (define (candidate-cost composites [tile #f])
    (define ranges (compress-composite-ranges composites))
    (+ (* (profile-coefficient 'draw_range_ns) (length ranges))
       (* (profile-coefficient 'clip_switch_ns) (length ranges))
       (* (profile-coefficient 'covered_pixel_ns)
          (if tile
              (* (profile-coefficient 'full_tile_multiplier)
                 (c-render-tile-width tile) (c-render-tile-height tile))
              (for/sum ([composite (in-list composites)]) (composite-area composite))))))

  (define (choose-render-strategy tile fragments complete budget-exceeded?)
    (define fragment-cost (if budget-exceeded? 1e30 (candidate-cost fragments)))
    (define complete-cost (candidate-cost complete))
    ;; 全 tile 路径只在碎片预算已超限时开放；普通局部 tile 不应为低估 full work 而退化。
    (define full-cost (if budget-exceeded? (candidate-cost complete tile) 1e30))
    (define candidates (list (cons 'fragment fragment-cost)
                             (cons 'complete-lower-range complete-cost)
                             (cons 'full-tile-redraw full-cost)))
    (define winner
      (for/fold ([best (first candidates)]) ([candidate (in-list (rest candidates))])
        (if (< (cdr candidate) (cdr best)) candidate best)))
    (values (car winner)
            (hash 'fragment fragment-cost
                  'complete-lower-range complete-cost
                  'full-tile-redraw full-cost)
            (if (and budget-exceeded? (eq? (car winner) 'complete-lower-range))
                'fragment-budget-complete-lower-range
                (if (eq? (car winner) 'full-tile-redraw)
                    'cost-model-full-tile-redraw
                    'cost-model-minimum))))

  ;; Tile culling 使用实际 glyph quad，而不是 text run/layout 的保守外框：先由 packet bounds
  ;; 剔除不相交 packet，再为命中的 packet 计算连续 placement subrange。
  (define (tile-rect tile)
    (list (c-render-tile-x tile) (c-render-tile-y tile)
          (c-render-tile-width tile) (c-render-tile-height tile)))
  (define (glyph-placement-screen-rect placement)
    (define pos (c-glyph-placement-ndc-pos placement))
    (define size (c-glyph-placement-ndc-size placement))
    (define half-width (/ (canvas-width) 2.0))
    (define half-height (/ (canvas-height) 2.0))
    (list (* (+ (first pos) 1.0) half-width)
          (* (- 1.0 (+ (second pos) (second size))) half-height)
          (* (first size) half-width)
          (* (second size) half-height)))
  (define (glyph-placement-effective-rect placement)
    (rect-intersection (glyph-placement-screen-rect placement)
                       (c-glyph-placement-clip-rect placement)))
  (define (rect-union* rects)
    (define x (apply min (map first rects)))
    (define y (apply min (map second rects)))
    (define right (apply max (map (lambda (rect) (+ (first rect) (third rect))) rects)))
    (define bottom (apply max (map (lambda (rect) (+ (second rect) (fourth rect))) rects)))
    (list x y (- right x) (- bottom y)))
  (define (compress-glyph-tile-ranges packet packet-index selected tile)
    ;; selected 是按 slot 递增的 `(placement . effective-rect)`；不同 text run 之间的空洞
    ;; 不会被合并，避免提交 tile 外 glyph instances。
    (define (finish first-slot previous-slot reverse-rects acc)
      (define raw-bounds (rect-union* (reverse reverse-rects)))
      (define bounds (rect-intersection raw-bounds (tile-rect tile)))
      (unless bounds
        (raise-syntax-error 'noir "selected glyph subrange has no tile intersection" #f))
      (cons (c-glyph-packet-range (c-glyph-packet-id packet) packet-index first-slot
                                   (add1 (- previous-slot first-slot)) bounds
                                   (c-glyph-packet-dynamic? packet))
            acc))
    (let loop ([remaining selected] [first-slot #f] [previous-slot #f] [reverse-rects '()] [acc '()])
      (cond
        [(null? remaining)
         (if first-slot (reverse (finish first-slot previous-slot reverse-rects acc)) (reverse acc))]
        [else
         (define placement (caar remaining))
         (define rect (cdar remaining))
         (define slot (c-glyph-placement-slot placement))
         (cond
           [(not first-slot)
            (loop (cdr remaining) slot slot (list rect) acc)]
           [(= slot (add1 previous-slot))
            (loop (cdr remaining) first-slot slot (cons rect reverse-rects) acc)]
           [else
            (loop (cdr remaining) slot slot (list rect)
                  (finish first-slot previous-slot reverse-rects acc))])]))
    )
  (define (compile-glyph-tile-ranges tile placements packets)
    (define target (tile-rect tile))
    (append-map
     (lambda (packet packet-index)
       ;; packet bounds 已与 packet 的 clip rect 相交；这是 packet-level early reject。
       (if (not (rect-intersection (c-glyph-packet-bounds packet) target))
           '()
           (let* ([first (c-glyph-packet-first-placement packet)]
                  [count (c-glyph-packet-placement-count packet)]
                  [packet-placements (take (drop placements first) count)]
                  [selected
                   (filter values
                           (for/list ([placement (in-list packet-placements)])
                             (define effective (glyph-placement-effective-rect placement))
                             (and effective
                                  (rect-intersection effective target)
                                  (cons placement effective))))])
             (compress-glyph-tile-ranges packet packet-index selected tile))))
     packets (range (length packets))))
  (define (assert-glyph-tile-culling! tiles placements packets root)
    (for ([tile (in-list tiles)])
      (define target (tile-rect tile))
      (for ([range (in-list (c-render-tile-glyph-packet-ranges tile))])
        (define packet-index (c-glyph-packet-range-packet-index range))
        (unless (and (exact-nonnegative-integer? packet-index) (< packet-index (length packets)))
          (raise-syntax-error 'noir "glyph tile range refers to an invalid packet index" (c-node-source root)))
        (define packet (list-ref packets packet-index))
        (unless (eq? (c-glyph-packet-range-packet-id range) (c-glyph-packet-id packet))
          (raise-syntax-error 'noir "glyph tile range packet ID disagrees with its index" (c-node-source root)))
        (define start (c-glyph-packet-range-first-placement range))
        (define end (+ start (c-glyph-packet-range-placement-count range)))
        (define packet-start (c-glyph-packet-first-placement packet))
        (define packet-end (+ packet-start (c-glyph-packet-placement-count packet)))
        (unless (and (<= packet-start start) (<= end packet-end) (< start end))
          (raise-syntax-error 'noir "glyph tile range escapes its packet placement interval" (c-node-source root)))
        (unless (and (rect-intersection (c-glyph-packet-range-bounds range) target)
                     (rect-intersection (c-glyph-packet-bounds packet) target))
          (raise-syntax-error 'noir "glyph tile range has no packet/tile bounds intersection" (c-node-source root)))
        (for ([placement (in-list (take (drop placements start) (- end start)))])
          (unless (and (glyph-placement-effective-rect placement)
                       (rect-intersection (glyph-placement-effective-rect placement) target))
            (raise-syntax-error 'noir "glyph tile range includes a glyph outside the tile" (c-node-source root))))
      )
    (void)))
  (define (attach-tile-draw-ranges tile composites placements packets)
    (define visible
      (sort (filter (lambda (composite)
                      (layout-intersects-tile? (c-composite-layout composite) tile))
                    composites)
            (lambda (left right)
              (or (< (c-composite-z-layer left) (c-composite-z-layer right))
                  (and (= (c-composite-z-layer left) (c-composite-z-layer right))
                       (< (c-composite-slot left) (c-composite-slot right)))))))
    (define-values (fragments budget-exceeded?) (coverage-partition visible))
    (when (null? fragments)
      (raise-syntax-error 'noir "compiled scissor tile has no visible fragment after coverage partitioning"))
    (define-values (strategy costs fallback-reason)
      (choose-render-strategy tile fragments visible budget-exceeded?))
    (define selected-composites
      (case strategy
        [(fragment) fragments]
        [(complete-lower-range full-tile-redraw) visible]))
    (struct-copy c-render-tile tile
                 [draw-ranges (compress-composite-ranges selected-composites)]
                 [glyph-packet-ranges (compile-glyph-tile-ranges tile placements packets)]
                 [fallback-reason fallback-reason]
                 [selected-strategy strategy]
                 [candidate-costs costs]))

  (define (c-glyph-packet-range->datum range)
    `(glyph-packet-range ',(c-glyph-packet-range-packet-id range)
                         ,(c-glyph-packet-range-packet-index range)
                         ,(c-glyph-packet-range-first-placement range)
                         ,(c-glyph-packet-range-placement-count range)
                         ',(c-glyph-packet-range-bounds range)
                         ,(c-glyph-packet-range-dynamic? range)))

  (define (c-draw-range->datum range)
    `(draw-range ,(c-draw-range-first-instance range)
                 ,(c-draw-range-instance-count range)
                 ,(c-draw-range-vertex-count range)
                 ',(c-draw-range-batch-key range)
                 ,(c-draw-range-z-layer range)
                 ',(c-draw-range-clip-stack-id range)
                 ',(c-draw-range-clip-rect range)
                 ',(c-draw-range-blend-mode range)
                 ,(c-draw-range-opaque? range)))

  (define (compile-render-schedules root layouts events tracks plans placements packets tasks)
    (define composites (compile-composites root layouts))
    (if (null? plans)
        '()
        (let* ([layout-by-id (for/hash ([layout (in-list layouts)])
                               (values (c-layout-id layout) layout))]
               ;; 动态数字的 glyph geometry 不会重排；将其固定 text rect 并入 Damage Plan，
               ;; 让 action tile 能在编译期选择 page-0 packet subrange，而非仅靠全局 scissor。
               [text-rects
                (append-map
                 (lambda (plan)
                   (for/list ([binding (in-list (c-action-plan-text-updates plan))])
                     (define layout (hash-ref layout-by-id (c-binding-node-id binding)))
                     (c-rect (c-binding-node-id binding)
                             (c-layout-x layout) (c-layout-y layout)
                             (c-layout-width layout) (c-layout-height layout))))
                 plans)]
               ;; 动态几何同样来自 action plan 的真实 instance binding；这使 progress 等
               ;; 基础原语可由组件生成任意稳定 ID，而无需 renderer schedule 知道组件名称。
               [geometry-rects
                (append-map
                 (lambda (plan)
                   (for/list ([binding (in-list (c-action-plan-instance-updates plan))])
                     (define layout (c-instance-binding-layout binding))
                     (c-rect (c-layout-id layout)
                             (c-layout-x layout) (c-layout-y layout)
                             (c-layout-width layout) (c-layout-height layout))))
                 plans)]
               [event-rects
                (for/list ([event (in-list events)])
                  ;; hover/pressed/release 都写同一 button instance；pressed y 偏移 2px，另留 2px raster guard。
                  (c-rect (c-event-node-id event) (c-event-x event) (c-event-y event)
                          (c-event-width event) (+ (c-event-height event) 4.0)))]
               ;; Scrollbar thumb is pointer-driven but has no Action Plan. Its immutable track rect
               ;; enters the same compile-time tile partition so drag can submit a local no-packets tile.
               [scrollbar-rects
                (for/list ([node (in-list (filter (lambda (candidate) (eq? (c-node-tag candidate) 'scrollbar))
                                                   (walk-nodes root)))])
                  (define layout (hash-ref layout-by-id (c-node-id node)))
                  (c-rect (c-node-id node) (c-layout-x layout) (c-layout-y layout)
                          (c-layout-width layout) (c-layout-height layout)))]
               [existing-rects (append text-rects geometry-rects event-rects scrollbar-rects)]
               ;; 仅为尚未被 action/event Damage Plan 覆盖的 focus field 补一块候选 tile。
               ;; 已具备 field tile 的旧 Scene 不改变 tile 顺序/编号；无关联 action 的 field 仍不需伪 refresh action。
               [focus-rects
                (for/list ([node (in-list (filter focusable-text-field? (walk-nodes root)))]
                           #:unless
                           (let ([layout (hash-ref layout-by-id (c-node-id node))])
                             (ormap (lambda (rect)
                                       (rect-intersection (layout-rect layout)
                                                          (list (c-rect-x rect) (c-rect-y rect)
                                                                (c-rect-width rect) (c-rect-height rect))))
                                     existing-rects)))
                  (define layout (hash-ref layout-by-id (c-node-id node)))
                  (c-rect (c-node-id node)
                          (c-layout-x layout) (c-layout-y layout)
                          (c-layout-width layout) (c-layout-height layout)))]
               [rects (append existing-rects focus-rects)]
               [tiles (reverse (foldl (lambda (rect acc) (insert-merged-tile (rect->tile rect) acc)) '() rects))]
               [covered-area (for/sum ([tile (in-list tiles)])
                               (* (c-render-tile-width tile) (c-render-tile-height tile)))]
                [coverage (/ covered-area (viewport-area))]
               [full? (>= coverage full-redraw-threshold)]
               [raw-final-tiles (if full? (list (c-render-tile 0.0 0.0 (canvas-width) (canvas-height) '(full-frame) '() '() 'full-redraw-threshold 'full-tile-redraw (hash 'fragment 1e30 'complete-lower-range 1e30 'full-tile-redraw 230400.0))) tiles)]
               [final-tiles (map (lambda (tile) (attach-tile-draw-ranges tile composites placements packets)) raw-final-tiles)])
          (assert-glyph-tile-culling! final-tiles placements packets root)
          (list (c-render-schedule
                 'concurrent-frame
                 (map c-frame-task-id tasks)
                 final-tiles coverage full? active-profile-id)))))

  ;; Task Selection 在所有 tiles 固化后执行。它只处理 compiler 已知的 action binding、
  ;; event rect 和 tile rect；runtime 不进行 damage union、hit geometry 或 tile 相交测试。
  (define (compile-action-aware-tile-selection root layouts events plans tasks schedules)
    (define schedule
      (or (and (pair? schedules) (car schedules))
          (raise-syntax-error 'noir "action tile selection requires a compiled render schedule" (c-node-source root))))
    (define tiles (c-render-schedule-tiles schedule))
    (define layout-by-id
      (for/hash ([layout (in-list layouts)]) (values (c-layout-id layout) layout)))
    (define plan-by-id
      (for/hash ([plan (in-list plans)]) (values (c-action-plan-id plan) plan)))
    (define (layout->rect layout) (layout-rect layout))
    (define (event-for-task task)
      (findf
       (lambda (event)
         (case (c-frame-task-kind task)
           [(hover) (eq? (c-frame-task-id task)
                          (string->symbol (format "hover-~a" (c-event-node-id event))))]
           [(pressed) (eq? (c-frame-task-id task)
                            (string->symbol (format "pressed-~a" (c-event-node-id event))))]
           [(release) (eq? (c-frame-task-id task)
                            (string->symbol (format "release-~a" (c-event-node-id event))))]
           [else #f]))
       events))
    (define (task-damage-rects task)
      (case (c-frame-task-kind task)
        [(transaction)
         ;; 所有成员均为 macro-validated editable fields；该 rect union 在编译期归约为 tile IDs。
         (for/list ([node (in-list (filter focusable-text-field? (walk-nodes root)))])
           (layout->rect (hash-ref layout-by-id (c-node-id node))))]
        [(action)
         (define plan (hash-ref plan-by-id (c-frame-task-id task)))
         (remove-duplicates
          (append
           (map layout->rect (c-action-plan-damage plan))
           (for/list ([binding (in-list (c-action-plan-text-updates plan))])
             (layout->rect (hash-ref layout-by-id (c-binding-node-id binding))))))]
        [(hover pressed release)
         (define event (or (event-for-task task)
                           (raise-syntax-error 'noir "transient task has no Event Map binding" (c-node-source root))))
         ;; Pressed/release 含 2px 位移与 2px guard，必须与 Render Schedule 的 event rect 同构。
         (list (list (c-event-x event) (c-event-y event)
                     (c-event-width event) (+ (c-event-height event) 4.0)))]
        [else
         (raise-syntax-error 'noir "task kind has no compiled damage rule" (c-node-source root))]))
    (define (select-tile-ids damage-rects)
      (for/list ([tile (in-list tiles)] [tile-id (in-naturals)]
                 #:when (ormap (lambda (damage) (rect-intersection (tile-rect tile) damage)) damage-rects))
        tile-id))
    (define task->tile-ids
      (for/hash ([task (in-list tasks)])
        (define ids (select-tile-ids (task-damage-rects task)))
        (when (null? ids)
          (raise-syntax-error 'noir "task damage does not select any compiled render tile" (c-node-source root)))
        (values (c-frame-task-id task) ids)))
    (define selected-plans
      (for/list ([plan (in-list plans)])
        (struct-copy c-action-plan plan [tile-ids (hash-ref task->tile-ids (c-action-plan-id plan))])))
    (define selected-tasks
      (for/list ([task (in-list tasks)])
        (struct-copy c-frame-task task [tile-ids (hash-ref task->tile-ids (c-frame-task-id task))])))
    ;; 每个 task 的 ID 必须严格递增且无重复；每个 damage rect 至少由一个 selected tile 覆盖。
    (for ([task (in-list selected-tasks)])
      (define ids (c-frame-task-tile-ids task))
      (unless (and (pair? ids) (equal? ids (sort (remove-duplicates ids) <)))
        (raise-syntax-error 'noir "task tile IDs must be non-empty, unique and ascending" (c-node-source root)))
      (for ([damage (in-list (task-damage-rects task))])
        (unless (ormap (lambda (tile-id) (rect-intersection (tile-rect (list-ref tiles tile-id)) damage)) ids)
          (raise-syntax-error 'noir "selected tile IDs do not cover task damage" (c-node-source root))))
      )
    (values selected-plans selected-tasks))

  (define (focusable-text-field? node)
    (and (eq? (c-node-tag node) 'text)
         (hash-ref (c-node-props node) 'focusable #f)))

  ;; Focus Graph 位于 layout/render schedule lowering 之后：field 只依赖既有 text-run layout，
  ;; Tab runtime 只索引 next/previous slot 并 OR compiler tile mask，绝不排序或做 rect 计算。
  (define (compile-focus-graph root layouts schedules state-indexes)
    (define fields (filter focusable-text-field? (walk-nodes root)))
    (if (null? fields)
        (c-focus-graph '() -1)
        (let* ([layout-by-id (for/hash ([layout (in-list layouts)])
                               (values (c-layout-id layout) layout))]
               [sorted (sort fields < #:key (lambda (node) (hash-ref (c-node-props node) 'tab-index)))]
               [indices (map (lambda (node) (hash-ref (c-node-props node) 'tab-index)) sorted)]
               [schedule (and (pair? schedules) (car schedules))]
               [tiles (if schedule (c-render-schedule-tiles schedule) '())]
               [count (length sorted)])
          (unless (= (length indices) (set-count (list->set indices)))
            (raise-syntax-error 'text-field "duplicate #:tab-index in Focus Graph" (c-node-source root)))
          (define entries
            (for/list ([node (in-list sorted)] [slot (in-naturals)])
              (define layout (hash-ref layout-by-id (c-node-id node)))
              (define tile-ids
                (for/list ([tile (in-list tiles)] [tile-id (in-naturals)]
                           #:when (rect-intersection (layout-rect layout) (tile-rect tile)))
                  tile-id))
              (when (and schedule (null? tile-ids))
                (raise-syntax-error 'text-field "focus field does not intersect any compiled render tile" (c-node-source node)))
              (define value (hash-ref (c-node-props node) 'value))
(c-focus-entry slot (c-node-id node) (second value)
                              (hash-ref state-indexes (second value)
                                        (lambda () (raise-syntax-error 'text-field "focus field state has no compiler slot" (c-node-source node))))
                              (hash-ref (c-node-props node) 'tab-index)
                             (modulo (+ slot 1) count)
                             (modulo (+ slot (- count 1)) count)
                             tile-ids (c-layout-instance-offset layout))))
          (for ([entry (in-list entries)])
            (unless (and (equal? (c-focus-entry-tile-ids entry)
                                (sort (remove-duplicates (c-focus-entry-tile-ids entry)) <))
                         (< (c-focus-entry-next-slot entry) count)
                         (< (c-focus-entry-previous-slot entry) count))
              (raise-syntax-error 'text-field "invalid compiler Focus Graph transition" (c-node-source root))))
          (c-focus-graph entries 0))))

  ;; Digit Register Keyboard Map：MVP 只允许 ASCII digit 0..9 和 Backspace。cursor 仍决定
  ;; 固定 glyph slot；register transition 则在同一键事件中维护 pending integer，完全不解析文本。
  (define (compile-keyboard-map root focus-graph state-initial-by-id)
    (define bindings (collect-glyph-bindings root))
    (define binding-by-node
      (for/hash ([binding (in-list bindings)]) (values (c-binding-node-id binding) binding)))
    (define node-by-id (for/hash ([node (in-list (walk-nodes root))]) (values (c-node-id node) node)))
    (define fields
      (for/list ([entry (in-list (c-focus-graph-entries focus-graph))])
        (define binding (hash-ref binding-by-node (c-focus-entry-node-id entry)
                                  (lambda ()
                                    (raise-syntax-error 'text-field "focus field has no fixed glyph binding" (c-node-source root)))))
        (unless (eq? (c-binding-state binding) (c-focus-entry-state entry))
          (raise-syntax-error 'text-field "focus field state disagrees with glyph binding" (c-node-source root)))
        (define max-chars (c-binding-glyph-count binding))
        (define field-node (hash-ref node-by-id (c-focus-entry-node-id entry)))
        (define charset (hash-ref (c-node-props field-node) 'charset 'digits))
        (define offsets
          (for/list ([index (in-range max-chars)])
            (+ (c-binding-offset binding) (* index glyph-instance-bytes))))
        (unless (and (equal? offsets (sort offsets <))
                     (andmap (lambda (offset) (= (modulo offset glyph-instance-bytes) 0)) offsets))
          (raise-syntax-error 'text-field "keyboard glyph ID offsets must be aligned and strictly increasing" (c-node-source root)))
        (cond
          [(eq? charset 'digits)
           (define initial-value
             (hash-ref state-initial-by-id (c-focus-entry-state entry)
                       (lambda ()
                         (raise-syntax-error 'text-field "digit register state has no compile-time initial integer" (c-node-source root)))))
           (define maximum-value (- (expt 10 max-chars) 1))
           (unless (and (exact-nonnegative-integer? initial-value) (<= initial-value maximum-value))
             (raise-syntax-error 'text-field
                                 (format "digit register initial value ~a exceeds fixed ~a-digit capacity" initial-value max-chars)
                                 (c-node-source root)))
           (c-keyboard-field (c-focus-entry-slot entry) (c-focus-entry-node-id entry)
                             (c-focus-entry-state entry) (c-focus-entry-state-index entry) max-chars charset offsets
                             (c-focus-entry-tile-ids entry) (c-digit-register 10 max-chars initial-value 0 maximum-value) #f)]
          [(eq? charset 'ascii-upper)
           (c-keyboard-field (c-focus-entry-slot entry) (c-focus-entry-node-id entry)
                             (c-focus-entry-state entry) (c-focus-entry-state-index entry) max-chars charset offsets
                             (c-focus-entry-tile-ids entry) #f
                             (c-ascii-text-register 'ascii-upper max-chars 0 0 ascii-atlas-page))]
          [else (raise-syntax-error 'text-field "unsupported compiler charset" (c-node-source field-node))])))
    (define transitions
      (append-map
       (lambda (field)
         (cond
           [(eq? (c-keyboard-field-charset field) 'digits)
            (define register (c-keyboard-field-digit-register field))
            (append
             (for/list ([digit (in-range 10)])
               (c-keyboard-transition (c-keyboard-field-focus-slot field)
                                      (string->symbol (format "digit-~a" digit))
                                      'insert digit 'advance (c-keyboard-field-tile-ids field)
                                      'append-digit (c-digit-register-radix register) digit))
             (list (c-keyboard-transition (c-keyboard-field-focus-slot field)
                                          'backspace 'backspace 0 'retreat
                                          (c-keyboard-field-tile-ids field)
                                          'drop-last (c-digit-register-radix register) 0)))]
           [(eq? (c-keyboard-field-charset field) 'ascii-upper)
            (append
             (for/list ([glyph-index (in-range 1 27)] [code (in-range (char->integer #\A) (add1 (char->integer #\Z)))])
               (c-keyboard-transition (c-keyboard-field-focus-slot field)
                                      (string->symbol (format "letter-~a" (integer->char code)))
                                      'insert (encode-glyph ascii-atlas-page glyph-index) 'advance
                                      (c-keyboard-field-tile-ids field)
                                      'append-char 0 code))
             (list (c-keyboard-transition (c-keyboard-field-focus-slot field)
                                          'space 'insert (encode-glyph ascii-atlas-page 0) 'advance
                                          (c-keyboard-field-tile-ids field) 'append-char 0 (char->integer #\space))
                   (c-keyboard-transition (c-keyboard-field-focus-slot field)
                                          'backspace 'backspace (encode-glyph ascii-atlas-page 0) 'retreat
                                          (c-keyboard-field-tile-ids field) 'drop-char 0 0)))]
           [else (error 'compile-keyboard-map "unsupported charset")]))
       fields))
    ;; 每 field 的 transition contract 都在展开期证明；ASCII 路径不复用十进制算术。
    (for ([field (in-list fields)])
      (define local (filter (lambda (transition)
                              (= (c-keyboard-transition-focus-slot transition)
                                 (c-keyboard-field-focus-slot field)))
                            transitions))
      (case (c-keyboard-field-charset field)
        [(digits)
         (define register (c-keyboard-field-digit-register field))
         (unless (= (length local) 11)
           (raise-syntax-error 'text-field "Keyboard Map must contain 10 digits plus Backspace per digit field" (c-node-source root)))
         (unless (and register (= (c-digit-register-radix register) 10)
                      (= (c-digit-register-max-digits register) (c-keyboard-field-max-chars field))
                      (= (c-digit-register-reset-value register) 0)
                      (= (c-digit-register-maximum-value register) (- (expt 10 (c-keyboard-field-max-chars field)) 1)))
           (raise-syntax-error 'text-field "invalid compiler Digit Register descriptor" (c-node-source root)))]
        [(ascii-upper)
         (define register (c-keyboard-field-ascii-text-register field))
         (define letters (take local 26))
         (define space-transition (list-ref local 26))
         (define backspace (last local))
         (unless (and register (= (length local) 28)
                      (eq? (c-ascii-text-register-charset register) 'ascii-upper)
                      (= (c-ascii-text-register-max-chars register) (c-keyboard-field-max-chars field))
                      (= (c-ascii-text-register-atlas-page register) ascii-atlas-page)
                      (equal? (map c-keyboard-transition-register-op letters) (make-list 26 'append-char))
                      (equal? (map c-keyboard-transition-register-operand letters)
                              (range (char->integer #\A) (add1 (char->integer #\Z))))
                      (eq? (c-keyboard-transition-register-op space-transition) 'append-char)
                      (= (c-keyboard-transition-register-operand space-transition) (char->integer #\space))
                      (eq? (c-keyboard-transition-register-op backspace) 'drop-char))
           (raise-syntax-error 'text-field "ASCII Text Register transition table is incomplete or non-canonical" (c-node-source root)))]
        [else (raise-syntax-error 'text-field "unsupported Keyboard Map charset" (c-node-source root))])
      (unless (andmap (lambda (transition)
                        (equal? (c-keyboard-transition-tile-ids transition)
                                (c-keyboard-field-tile-ids field)))
                      local)
        (raise-syntax-error 'text-field "Keyboard transition tile IDs disagree with focus field" (c-node-source root))))
    (c-keyboard-map fields transitions))

  (define (compile-transaction-plans transactions focus-graph)
    (define focus-by-state
      (for/hash ([entry (in-list (c-focus-graph-entries focus-graph))])
        (values (c-focus-entry-state entry) entry)))
    (for/list ([transaction (in-list (sort transactions symbol<? #:key c-transaction-id))]
               [index (in-naturals)])
      (define entries
        (for/list ([state-id (in-list (c-transaction-states transaction))])
          (hash-ref focus-by-state state-id
                    (lambda () (raise-syntax-error 'commit-group
                                                     (format "state ~a has no editable field binding" state-id)
                                                     #f)))))
      (define field-slots (map c-focus-entry-slot entries))
      (define state-indices (map c-focus-entry-state-index entries))
      (unless (and (= (length field-slots) (length (remove-duplicates field-slots)))
                   (= (length state-indices) (length (remove-duplicates state-indices))))
        (raise-syntax-error 'commit-group "transaction fields/state slots must be unique" #f))
      (c-transaction-plan index (c-transaction-id transaction) field-slots state-indices
                          (sort (remove-duplicates (append-map c-focus-entry-tile-ids entries)) <))))

  ;; Command Map 独立于 digit Keyboard Map。Enter 可以引用已确定 action plan，也可以是
  ;; `commit`：后者把该 slot 的 pending digit register 写入 field 已绑定 state；两者都无 runtime name lookup。
  (define (compile-keyboard-command-map root focus-graph action-plans action-indexes transaction-plans)
    (define node-by-id (for/hash ([node (in-list (walk-nodes root))]) (values (c-node-id node) node)))
    (define plan-by-id (for/hash ([plan (in-list action-plans)]) (values (c-action-plan-id plan) plan)))
    (define transaction-by-id (for/hash ([plan (in-list transaction-plans)]) (values (c-transaction-plan-id plan) plan)))
    (define transitions
      (append-map
       (lambda (entry)
         (define node (hash-ref node-by-id (c-focus-entry-node-id entry)))
         (define enter-spec (hash-ref (c-node-props node) 'on-enter #f))
         (define reset (c-keyboard-command-transition (c-focus-entry-slot entry) 'escape 'reset #f #f #f #f #f
                                                      (c-focus-entry-tile-ids entry)))
         (cond
           [(not enter-spec) (list reset)]
           [(eq? enter-spec 'commit)
            ;; target state 与 field/digit-register binding 是同一 compile-time symbol；无需 action、damage union 或 lookup。
            (list (c-keyboard-command-transition (c-focus-entry-slot entry) 'enter 'commit-pending-register #f #f #f
                                                 (c-focus-entry-state entry) (c-focus-entry-state-index entry)
                                                 (c-focus-entry-tile-ids entry))
                  reset)]
           [(hash-has-key? transaction-by-id enter-spec)
            (define plan (hash-ref transaction-by-id enter-spec))
            (unless (member (c-focus-entry-slot entry) (c-transaction-plan-field-slots plan))
              (raise-syntax-error 'text-field "transaction Enter binding must include its field slot" (c-node-source node)))
            (list (c-keyboard-command-transition (c-focus-entry-slot entry) 'enter 'commit-group #f #f
                                                 (c-transaction-plan-index plan) #f #f
                                                 (c-transaction-plan-tile-ids plan))
                  reset)]
           [else
            (define plan (hash-ref plan-by-id enter-spec
                                   (lambda ()
                                     (raise-syntax-error 'text-field "#:on-enter must be `commit`, a declared commit-group ID, or an action ID" (c-node-source node)))))
            (define tile-ids
              (sort (remove-duplicates (append (c-focus-entry-tile-ids entry)
                                                 (c-action-plan-tile-ids plan))) <))
            (list (c-keyboard-command-transition (c-focus-entry-slot entry) 'enter 'action enter-spec
                                                 (hash-ref action-indexes enter-spec) #f #f #f tile-ids)
                  reset)]))
       (c-focus-graph-entries focus-graph)))
    (for ([entry (in-list (c-focus-graph-entries focus-graph))])
      (define local (filter (lambda (transition) (= (c-keyboard-command-transition-focus-slot transition)
                                                     (c-focus-entry-slot entry))) transitions))
      (unless (and (pair? local)
                   (= 1 (count (lambda (transition) (eq? (c-keyboard-command-transition-key transition) 'escape)) local))
                   (<= (length local) 2))
        (raise-syntax-error 'text-field "Keyboard Command Map must contain Escape and at most one Enter per field" (c-node-source root)))
      (for ([transition (in-list local)] #:when (eq? (c-keyboard-command-transition-key transition) 'enter))
        (cond [(eq? (c-keyboard-command-transition-kind transition) 'commit-pending-register)
               (unless (and (not (c-keyboard-command-transition-action transition))
                            (eq? (c-keyboard-command-transition-target-state transition) (c-focus-entry-state entry))
                            (equal? (c-keyboard-command-transition-tile-ids transition) (c-focus-entry-tile-ids entry)))
                 (raise-syntax-error 'text-field "commit-pending-register must target only its field state and tile" (c-node-source root)))]
               [(eq? (c-keyboard-command-transition-kind transition) 'commit-group)
                (define plan (list-ref transaction-plans (c-keyboard-command-transition-transaction-index transition)))
                (unless (and (not (c-keyboard-command-transition-action transition))
                             (not (c-keyboard-command-transition-target-state transition))
                             (member (c-focus-entry-slot entry) (c-transaction-plan-field-slots plan))
                             (equal? (c-keyboard-command-transition-tile-ids transition) (c-transaction-plan-tile-ids plan)))
                  (raise-syntax-error 'text-field "commit-group Enter disagrees with transaction plan" (c-node-source root)))]
               [(eq? (c-keyboard-command-transition-kind transition) 'action)
                (unless (and (c-keyboard-command-transition-action transition)
                             (not (c-keyboard-command-transition-target-state transition))
                             (not (c-keyboard-command-transition-transaction-index transition)))
                  (raise-syntax-error 'text-field "action Enter transition has invalid commit target metadata" (c-node-source root)))]
               [else (raise-syntax-error 'text-field "unsupported Enter command kind" (c-node-source root))])))
    (c-keyboard-command-map transitions))

  (define (compile-scene root)
    (define total (count-nodes root))
    (define dynamic (count-dynamic root))
    (define updates (collect-update-plan root))
    (define bindings (collect-glyph-bindings root))
    (define glyph-capacity
      (for/sum ([binding (in-list bindings)]) (c-binding-glyph-count binding)))
    (values total dynamic
            (hash 'node_capacity total
                  'instance_capacity total
                  'glyph_capacity glyph-capacity)
            updates))

  ;; 将 compile-time IR 转成 runtime 构造表达式。props 均是 DSL 已验证的
  ;; literal/symbol/list，因此可安全 quote；运行期无 parser。
  (define (node->datum n)
    `(ui-node ',(c-node-tag n)
              ',(c-node-id n)
              (hash
               ,@(append-map
                  (lambda (kv) (list `(quote ,(car kv)) `(quote ,(cdr kv))))
                  (hash->list (c-node-props n))))
              (list ,@(map node->datum (c-node-children n)))
              ',(syntax-source (c-node-source n))))

  (define (layout-entry->datum layout node-by-id state-by-id)
    ;; 目标 viewport 也是 Noir 受限 Layout Plan 的一部分；因此 NDC 变换
    ;; 在宏展开期完成，host 无需重新计算 rect 或做像素到 clip-space 转换。
    (define x (c-layout-x layout))
    (define y (c-layout-y layout))
    (define full-width (c-layout-width layout))
    (define height (c-layout-height layout))
    (define node (hash-ref node-by-id (c-layout-id layout)))
    (define progress-state (dynamic-progress-state node))
    ;; progress 的 rect 地址不变，但初始 size.x 由初始状态预先特化；以后 action
    ;; 仅向该 slot 的 size.x 字段写 4 字节。
    (define rendered-width
      (if progress-state
          (* full-width (/ (hash-ref state-by-id progress-state) (hash-ref (c-node-props node) 'max)))
          full-width))
    (define ndc-pos (list (- (* 2.0 (/ x (canvas-width))) 1.0)
                          (- 1.0 (* 2.0 (/ (+ y height) (canvas-height))))))
    (define ndc-size (list (* 2.0 (/ rendered-width (canvas-width)))
                           (* 2.0 (/ height (canvas-height)))))
    `(hash 'id ',(c-layout-id layout)
           'tag ',(c-layout-tag layout)
           'x ,x 'y ,y 'width ,full-width 'height ,height
           'elevation ,(c-layout-elevation layout)
           'ndc_pos ',ndc-pos
           'ndc_size ',ndc-size
           'color ',(c-layout-color layout)
           'glyph_offset ,(c-layout-glyph-offset layout)
           'glyph_count ,(c-layout-glyph-count layout)
           'atlas_page ,(c-layout-atlas-page layout)
           'glyph_ids ',(c-layout-glyph-ids layout)
           'glyph_advances ',(c-layout-glyph-advances layout)
           'instance_offset ,(c-layout-instance-offset layout)
           'vertex_count ,(c-layout-vertex-count layout)))

  (define (layout-plan->datum layouts root states)
    (define node-by-id (for/hash ([node (in-list (walk-nodes root))]) (values (c-node-id node) node)))
    (define state-by-id (for/hash ([state (in-list states)]) (values (c-state-id state) (c-state-initial state))))
    `(list ,@(map (lambda (layout) (layout-entry->datum layout node-by-id state-by-id)) layouts)))

  (define (compile-virtual-list-plans root layouts glyph-placements)
    (define layout-by-id (for/hash ([layout (in-list layouts)]) (values (c-layout-id layout) layout)))
    (define node-by-id (for/hash ([candidate (in-list (walk-nodes root))])
                         (values (c-node-id candidate) candidate)))
    ;; A virtual list owns a separate, dense static row-tile arena where row i always
    ;; maps to tile i. Each row also owns immutable lists of QuadInstance and glyph
    ;; placement slots so scroll never traverses UI nodes or discovers GPU ranges.
    (for/list ([node (in-list (filter (lambda (node) (eq? (c-node-tag node) 'virtual-list))
                                       (walk-nodes root)))])
      (define props (c-node-props node))
      (define row-ids (map c-node-id (c-node-children node)))
      (define visible-rows (hash-ref props 'visible-rows))
      (define row-subtree-ids
        (for/list ([row-id (in-list row-ids)])
          (map c-node-id (walk-nodes (hash-ref node-by-id row-id)))))
      (define row-instance-offsets
        (for/list ([subtree-ids (in-list row-subtree-ids)])
          (for/list ([node-id (in-list subtree-ids)] #:when (hash-has-key? layout-by-id node-id))
            (c-layout-instance-offset (hash-ref layout-by-id node-id)))))
      (define row-glyph-slots
        (for/list ([subtree-ids (in-list row-subtree-ids)])
          (for/list ([placement (in-list glyph-placements)]
                     #:when (member (c-glyph-placement-node-id placement) subtree-ids))
            (c-glyph-placement-slot placement))))
      (define (contiguous-range who values source)
        (define ordered (sort values <))
        (unless (and (pair? ordered)
                     (for/and ([left (in-list ordered)] [right (in-list (rest ordered))])
                       (= right (add1 left))))
          (raise-syntax-error 'virtual-list (format "~a must occupy one compiler-fixed contiguous range" who) source))
        (hash 'first (first ordered) 'count (length ordered)))
      (define row-draw-ranges
        (for/list ([offsets (in-list row-instance-offsets)])
          (contiguous-range "row quad instances" (map (lambda (offset) (/ offset 44)) offsets) (c-node-source node))))
      (define row-glyph-subranges
        (for/list ([slots (in-list row-glyph-slots)])
          (contiguous-range "row glyph placements" slots (c-node-source node))))
      (define row-layouts
        (for/list ([subtree-ids (in-list row-subtree-ids)])
          (for/list ([node-id (in-list subtree-ids)] #:when (hash-has-key? layout-by-id node-id))
            (hash-ref layout-by-id node-id))))
      (define row-glyph-placements
        (for/list ([subtree-ids (in-list row-subtree-ids)])
          (filter (lambda (placement) (member (c-glyph-placement-node-id placement) subtree-ids)) glyph-placements)))
      (define capacity (hash-ref props 'capacity))
      (define logical-capacity (hash-ref props 'logical-capacity capacity))
      (define physical-slots (hash-ref props 'physical-slots capacity))
      (define recycling? (hash-ref props 'recycling? #f))
      (define logical-data-ids (hash-ref props 'logical-data-ids row-ids))
      (define data-register-table (hash-ref props 'data-register-table #f))
      (define data-update-batches (hash-ref props 'data-update-batches '()))
      ;; Literal recycling scenes retain labels for exact patch recipes. Compact register tables
      ;; carry only their seed/width artifact and therefore never serialize a logical label vector.
      (define logical-labels (hash-ref props 'logical-labels (make-list logical-capacity "")))
      (define initial-ring-slots (range physical-slots))
      (define row-height (hash-ref props 'row-height))
      (define max-scroll (- (if recycling? logical-capacity capacity) visible-rows))
      (define list-layout (hash-ref layout-by-id (c-node-id node)))
      (define scissor (hash 'x (c-layout-x list-layout)
                            'y (c-layout-y list-layout)
                            'width (c-layout-width list-layout)
                            'height (c-layout-height list-layout)))
      (define (visible? row-index viewport-slot)
        (and (<= viewport-slot row-index) (< row-index (+ viewport-slot visible-rows))))
      (define (target-layout-y layout row-index viewport-slot)
        (if (visible? row-index viewport-slot)
            (- 1.0 (* 2.0 (/ (+ (- (c-layout-y layout) (* viewport-slot row-height))
                                (c-layout-height layout))
                             (canvas-height))))
            -3.0))
      (define (target-glyph-y placement row-index viewport-slot)
        (if (visible? row-index viewport-slot)
            (- (second (c-glyph-placement-ndc-pos placement))
               (* viewport-slot (/ (* 2.0 row-height) (canvas-height))))
            -3.0))
      (define (transition from-slot to-slot)
        (define instance-y-patches
          (append-map
           (lambda (row-index layouts-for-row)
             (if (or (visible? row-index from-slot) (visible? row-index to-slot))
                 (for/list ([layout (in-list layouts-for-row)])
                   (hash 'offset (+ (c-layout-instance-offset layout) 4)
                         'y (target-layout-y layout row-index to-slot)))
                 '()))
           (range capacity) row-layouts))
        (define glyph-y-patches
          (append-map
           (lambda (row-index placements-for-row)
             (if (or (visible? row-index from-slot) (visible? row-index to-slot))
                 (for/list ([placement (in-list placements-for-row)])
                   (hash 'offset (+ (* (c-glyph-placement-slot placement) 48) 4)
                         'y (target-glyph-y placement row-index to-slot)))
                 '()))
           (range capacity) row-glyph-placements))
        (c-virtual-scroll-transition from-slot to-slot
                                     (range to-slot (+ to-slot visible-rows))
                                     instance-y-patches glyph-y-patches '() scissor))
      ;; A recycling viewport uses a physical ring: slot p owns logical row
      ;; target + ((p - target) mod physical-slots). All arithmetic is emitted here,
      ;; so the Rust event loop only indexes the corresponding transition entry.
      (define (recycling-transition from-slot to-slot)
        (define (logical-for-slot physical-slot viewport-slot)
          (+ viewport-slot (modulo (- physical-slot viewport-slot) physical-slots)))
        (define (slot-visible-index physical-slot viewport-slot)
          (modulo (- physical-slot viewport-slot) physical-slots))
        (define (slot-y layout physical-slot viewport-slot)
          (define local-index (slot-visible-index physical-slot viewport-slot))
          (if (< local-index visible-rows)
              (- 1.0 (* 2.0 (/ (+ (c-layout-y layout) (* local-index row-height)
                                   (c-layout-height layout)) (canvas-height))))
              -3.0))
        (define (slot-glyph-y placement physical-slot viewport-slot)
          (define local-index (slot-visible-index physical-slot viewport-slot))
          (if (< local-index visible-rows)
              (- (second (c-glyph-placement-ndc-pos placement))
                 (* local-index (/ (* 2.0 row-height) (canvas-height))))
              -3.0))
        (define (logical-glyph-ids logical-index glyph-count)
          (if (< logical-index logical-capacity)
              (let-values ([(page glyphs advances)
                            (shape-static-ascii 'virtual-list (list-ref logical-labels logical-index) (c-node-source node))])
                (append glyphs (make-list (max 0 (- glyph-count (length glyphs))) (encode-glyph ascii-atlas-page 0))))
              (make-list glyph-count (encode-glyph ascii-atlas-page 0))))
        (define instance-y-patches
          (append-map (lambda (physical-slot layouts-for-row)
                        (for/list ([layout (in-list layouts-for-row)])
                          (hash 'offset (+ (c-layout-instance-offset layout) 4)
                                'y (slot-y layout physical-slot to-slot))))
                      (range physical-slots) row-layouts))
        (define glyph-y-patches
          (append-map (lambda (physical-slot placements-for-row)
                        (for/list ([placement (in-list placements-for-row)])
                          (hash 'offset (+ (* (c-glyph-placement-slot placement) 48) 4)
                                'y (slot-glyph-y placement physical-slot to-slot))))
                      (range physical-slots) row-glyph-placements))
        (define glyph-id-patches
          (append-map (lambda (physical-slot placements-for-row)
                        (define glyphs (logical-glyph-ids (logical-for-slot physical-slot to-slot) (length placements-for-row)))
                        (for/list ([placement (in-list placements-for-row)] [glyph-id (in-list glyphs)])
                          (hash 'offset (c-glyph-placement-glyph-byte-offset placement) 'glyph_id glyph-id)))
                      (range physical-slots) row-glyph-placements))
        (define visible-slots
          (for/list ([logical-index (in-range to-slot (+ to-slot visible-rows))])
            (modulo logical-index physical-slots)))
        (c-virtual-scroll-transition from-slot to-slot visible-slots instance-y-patches glyph-y-patches glyph-id-patches scissor))
      (define scroll-transitions
        (if data-register-table
            '()
            (append-map (lambda (slot)
                          (append (if (< slot max-scroll) (list ((if recycling? recycling-transition transition) slot (add1 slot))) '())
                                  (if (> slot 0) (list ((if recycling? recycling-transition transition) slot (sub1 slot))) '())))
                        (range (add1 max-scroll)))))
      ;; The first viewport is the canonical row-tile prefix.
      (define visible-tile-ids (range visible-rows))
      (c-virtual-list-plan (c-node-id node)
                           capacity logical-capacity physical-slots recycling? logical-data-ids logical-labels initial-ring-slots data-register-table data-update-batches
                           visible-rows row-height (hash-ref props 'viewport-height)
                           row-ids
                           (map (lambda (row-id) (c-layout-instance-offset (hash-ref layout-by-id row-id))) row-ids)
                           row-instance-offsets row-glyph-slots row-draw-ranges row-glyph-subranges visible-tile-ids scroll-transitions)))

  (define (virtual-scroll-transition->datum transition)
    `(virtual-scroll-transition
      ,(c-virtual-scroll-transition-from-slot transition)
      ,(c-virtual-scroll-transition-to-slot transition)
      ',(c-virtual-scroll-transition-visible-row-tile-ids transition)
      ',(c-virtual-scroll-transition-instance-y-patches transition)
      ',(c-virtual-scroll-transition-glyph-y-patches transition)
      ',(c-virtual-scroll-transition-glyph-id-patches transition)
      ',(c-virtual-scroll-transition-scissor transition)))

  (define (compile-scrollbar-plans root layouts virtual-list-plans render-schedules)
    (define list-by-id (for/hash ([plan (in-list virtual-list-plans)])
                         (values (c-virtual-list-plan-id plan) plan)))
    (define layout-by-id (for/hash ([layout (in-list layouts)])
                           (values (c-layout-id layout) layout)))
    (define seen-ids (mutable-set))
    (for/list ([node (in-list (filter (lambda (candidate) (eq? (c-node-tag candidate) 'scrollbar))
                                       (walk-nodes root)))])
      (define id (c-node-id node))
      (define list-id (hash-ref (c-node-props node) 'list-id))
      (define list-plan
        (hash-ref list-by-id list-id
                  (lambda () (raise-syntax-error 'scrollbar "#:for must refer to a virtual-list in the same static root" (c-node-source node)))))
      (unless (set-add! seen-ids id)
        (raise-syntax-error 'scrollbar "duplicate scrollbar ID" (c-node-source node)))
      (define track (hash-ref layout-by-id id))
      (define thumb-id (component-child-id id 'thumb))
      (define thumb (hash-ref layout-by-id thumb-id
                              (lambda () (raise-syntax-error 'scrollbar "compiler did not materialize fixed thumb node" (c-node-source node)))))
      (define max-viewport (- (c-virtual-list-plan-logical-capacity list-plan)
                              (c-virtual-list-plan-visible-rows list-plan)))
      (unless (> max-viewport 0)
        (raise-syntax-error 'scrollbar "requires a virtual-list with logical_capacity > visible_rows" (c-node-source node)))
      (unless (and (= (c-layout-width track) (c-layout-width thumb))
                   (<= (c-layout-height thumb) (c-layout-height track)))
        (raise-syntax-error 'scrollbar "thumb must be a fixed in-track rect" (c-node-source node)))
      (define tile-ids
        (sort (remove-duplicates
               (append-map
                (lambda (schedule)
                  (for/list ([tile (in-list (c-render-schedule-tiles schedule))]
                             [tile-id (in-naturals)]
                             #:when (or (member id (c-render-tile-nodes tile))
                                        (member thumb-id (c-render-tile-nodes tile))))
                    tile-id))
                render-schedules))
              <))
      (unless (pair? tile-ids)
        (raise-syntax-error 'scrollbar "track/thumb must have a compiler render tile" (c-node-source node)))
      (c-scrollbar-plan id list-id id thumb-id
                        (c-layout-instance-offset track) (c-layout-instance-offset thumb)
                        (c-layout-x track) (c-layout-y track) (c-layout-width track) (c-layout-height track)
                        (c-layout-height thumb) max-viewport tile-ids 2 'logical-mod-physical-slots)))

  (define (scrollbar-plan->datum plan)
    `(scrollbar-plan ',(c-scrollbar-plan-id plan)
                     ',(c-scrollbar-plan-list-id plan)
                     ',(c-scrollbar-plan-track-id plan)
                     ',(c-scrollbar-plan-thumb-id plan)
                     ,(c-scrollbar-plan-track-instance-offset plan)
                     ,(c-scrollbar-plan-thumb-instance-offset plan)
                     ,(c-scrollbar-plan-track-x plan)
                     ,(c-scrollbar-plan-track-y plan)
                     ,(c-scrollbar-plan-track-width plan)
                     ,(c-scrollbar-plan-track-height plan)
                     ,(c-scrollbar-plan-thumb-height plan)
                     ,(c-scrollbar-plan-max-viewport plan)
                     ',(c-scrollbar-plan-tile-ids plan)
                     ,(c-scrollbar-plan-packet-worklist-index plan)
                     ',(c-scrollbar-plan-physical-slot-rule plan)))

  (define (scrollbar-plans->datum plans)
    `(list ,@(map scrollbar-plan->datum plans)))

  (define (manifest-ref who object key source)
    (define missing (gensym 'missing))
    (define value (hash-ref object (string->symbol key) missing))
    (define resolved (if (eq? value missing) (hash-ref object key missing) value))
    (when (eq? resolved missing)
      (raise-syntax-error who (format "font manifest is missing ~a" key) source))
    resolved)

  (define (font-asset-source-path source relative)
    (define from-project (simplify-path (build-path (current-directory) relative)))
    (cond
      [(file-exists? from-project) from-project]
      [else
       (define origin (syntax-source source))
       (define base (if (path? origin) (or (path-only origin) (current-directory)) (current-directory)))
       (simplify-path (build-path base relative))]))

  (define (parse-font-asset-forms forms)
    (for/list ([form (in-list forms)])
      (syntax-parse form
        #:datum-literals (font-asset)
        [(font-asset #:manifest manifest:string #:atlas atlas:string)
         (c-font-asset-spec (syntax-e #'manifest) (syntax-e #'atlas) form)]
        [_ (raise-syntax-error 'font-asset "expected (font-asset #:manifest relative-path #:atlas relative-path)" form)])))

  (define (compile-font-asset-plans specs)
    (define seen (mutable-set))
    (for/list ([spec (in-list specs)])
      (define manifest-source (font-asset-source-path (c-font-asset-spec-source spec) (c-font-asset-spec-manifest-path spec)))
      (define atlas-source (font-asset-source-path (c-font-asset-spec-source spec) (c-font-asset-spec-atlas-path spec)))
      (unless (file-exists? manifest-source)
        (raise-syntax-error 'font-asset "manifest path does not exist at macro expansion" (c-font-asset-spec-source spec)))
      (unless (file-exists? atlas-source)
        (raise-syntax-error 'font-asset "atlas path does not exist at macro expansion" (c-font-asset-spec-source spec)))
      (define manifest (call-with-input-file manifest-source read-json))
      (unless (equal? (manifest-ref 'font-asset manifest "schema" (c-font-asset-spec-source spec)) "noir-font-asset-manifest-v1")
        (raise-syntax-error 'font-asset "manifest schema must be noir-font-asset-manifest-v1" (c-font-asset-spec-source spec)))
      (unless (= (manifest-ref 'font-asset manifest "revision" (c-font-asset-spec-source spec)) 1)
        (raise-syntax-error 'font-asset "manifest revision must be 1" (c-font-asset-spec-source spec)))
      (define face-id (manifest-ref 'font-asset manifest "face_id" (c-font-asset-spec-source spec)))
      (unless (and (string? face-id) (not (string=? face-id "")))
        (raise-syntax-error 'font-asset "manifest face_id must be non-empty" (c-font-asset-spec-source spec)))
      (when (set-member? seen face-id)
        (raise-syntax-error 'font-asset "font asset face_id must be unique" (c-font-asset-spec-source spec)))
      (set-add! seen face-id)
      (unless (equal? (manifest-ref 'font-asset manifest "renderer_kind" (c-font-asset-spec-source spec)) "atlas-gray")
        (raise-syntax-error 'font-asset "v1 only accepts renderer_kind atlas-gray" (c-font-asset-spec-source spec)))
      (define atlas (manifest-ref 'font-asset manifest "atlas" (c-font-asset-spec-source spec)))
      (define metrics (manifest-ref 'font-asset manifest "metrics" (c-font-asset-spec-source spec)))
      (define glyphs (manifest-ref 'font-asset manifest "glyphs" (c-font-asset-spec-source spec)))
      (define glyph-count (manifest-ref 'font-asset manifest "glyph_count" (c-font-asset-spec-source spec)))
      (unless (and (list? glyphs) (exact-nonnegative-integer? glyph-count) (= (length glyphs) glyph-count)
                   (equal? (map (lambda (glyph) (manifest-ref 'font-asset glyph "glyph_id" (c-font-asset-spec-source spec))) glyphs) (range glyph-count)))
        (raise-syntax-error 'font-asset "manifest glyph IDs must be dense 0..glyph_count-1" (c-font-asset-spec-source spec)))
      (define width (manifest-ref 'font-asset atlas "width" (c-font-asset-spec-source spec)))
      (define height (manifest-ref 'font-asset atlas "height" (c-font-asset-spec-source spec)))
      (define channels (manifest-ref 'font-asset atlas "channels" (c-font-asset-spec-source spec)))
      (unless (and (exact-positive-integer? width) (exact-positive-integer? height) (= channels 1))
        (raise-syntax-error 'font-asset "atlas must have positive width/height and one R8 channel" (c-font-asset-spec-source spec)))
      (unless (= (file-size atlas-source) (* width height channels))
        (raise-syntax-error 'font-asset "atlas R8 byte length does not match manifest dimensions" (c-font-asset-spec-source spec)))
      ;; Persist only compiler-internal manifest metrics. Scene emits resolved placement
      ;; UVs and advances, while Rust rereads this same manifest for startup proof.
      (define compiled-glyphs
        (for/list ([glyph (in-list glyphs)])
          (define glyph-id (manifest-ref 'font-asset glyph "glyph_id" (c-font-asset-spec-source spec)))
          (define codepoint (manifest-ref 'font-asset glyph "codepoint" (c-font-asset-spec-source spec)))
          (define character (manifest-ref 'font-asset glyph "character" (c-font-asset-spec-source spec)))
          (define x (manifest-ref 'font-asset glyph "x" (c-font-asset-spec-source spec)))
          (define y (manifest-ref 'font-asset glyph "y" (c-font-asset-spec-source spec)))
          (define glyph-width (manifest-ref 'font-asset glyph "width" (c-font-asset-spec-source spec)))
          (define glyph-height (manifest-ref 'font-asset glyph "height" (c-font-asset-spec-source spec)))
          (define advance (manifest-ref 'font-asset glyph "advance" (c-font-asset-spec-source spec)))
          (define bearing-x (manifest-ref 'font-asset glyph "bearing_x" (c-font-asset-spec-source spec)))
          (define bearing-y (manifest-ref 'font-asset glyph "bearing_y" (c-font-asset-spec-source spec)))
          (unless (and (exact-nonnegative-integer? codepoint) (string? character) (= (string-length character) 1)
                       (exact-nonnegative-integer? x) (exact-nonnegative-integer? y)
                       (exact-positive-integer? glyph-width) (exact-positive-integer? glyph-height)
                       (<= (+ x glyph-width) width) (<= (+ y glyph-height) height)
                       (real? advance) (> advance 0.0) (real? bearing-x) (real? bearing-y))
            (raise-syntax-error 'font-asset "manifest glyph has invalid proportional metrics or atlas rectangle" (c-font-asset-spec-source spec)))
          (c-font-glyph glyph-id codepoint character x y glyph-width glyph-height advance bearing-x bearing-y)))
      (c-font-asset-plan face-id (c-font-asset-spec-manifest-path spec) (c-font-asset-spec-atlas-path spec)
                         (manifest-ref 'font-asset manifest "font_sha256" (c-font-asset-spec-source spec))
                         (manifest-ref 'font-asset manifest "atlas_sha256" (c-font-asset-spec-source spec))
                         width height channels
                         (manifest-ref 'font-asset metrics "pixel_size" (c-font-asset-spec-source spec))
                         (manifest-ref 'font-asset metrics "line_height" (c-font-asset-spec-source spec))
                         0 glyph-count 2 "registered-inactive" compiled-glyphs)))

  (define (parse-dynamic-font-cell-asset-forms forms)
    (for/list ([form (in-list forms)])
      (syntax-parse form
        #:datum-literals (dynamic-font-cell-asset)
        [(dynamic-font-cell-asset #:manifest manifest:string #:atlas atlas:string)
         (c-font-asset-spec (syntax-e #'manifest) (syntax-e #'atlas) form)]
        [_ (raise-syntax-error 'dynamic-font-cell-asset
                               "expected (dynamic-font-cell-asset #:manifest relative-path #:atlas relative-path)"
                               form)])))

  (define (compile-dynamic-font-cell-asset specs)
    (unless (= (length specs) 1)
      (raise-syntax-error 'dynamic-font-cell-asset "expects exactly one page-3 dynamic font asset declaration" #f))
    (define spec (car specs))
    (define source (c-font-asset-spec-source spec))
    (define manifest-source (font-asset-source-path source (c-font-asset-spec-manifest-path spec)))
    (define atlas-source (font-asset-source-path source (c-font-asset-spec-atlas-path spec)))
    (unless (file-exists? manifest-source)
      (raise-syntax-error 'dynamic-font-cell-asset "manifest path does not exist at macro expansion" source))
    (unless (file-exists? atlas-source)
      (raise-syntax-error 'dynamic-font-cell-asset "atlas path does not exist at macro expansion" source))
    (define manifest (call-with-input-file manifest-source read-json))
    (define (ref key) (manifest-ref 'dynamic-font-cell-asset manifest key source))
    (unless (and (equal? (ref "schema") "noir-font-asset-manifest-v1") (= (ref "revision") 1)
                 (equal? (ref "renderer_kind") "atlas-gray")
                 (equal? (ref "coverage_policy") "tabular-body-v1")
                 (equal? (ref "advance_policy") "fixed-tabular")
                 (= (ref "fixed_advance") 10.0))
      (raise-syntax-error 'dynamic-font-cell-asset
                          "manifest must be tabular-body-v1 atlas-gray with fixed-tabular 10.0px advance"
                          source))
    (define face-id (ref "face_id"))
    (unless (equal? face-id "noir-table-body-mono-16")
      (raise-syntax-error 'dynamic-font-cell-asset "v1 requires face_id noir-table-body-mono-16" source))
    (define atlas (ref "atlas"))
    (define width (manifest-ref 'dynamic-font-cell-asset atlas "width" source))
    (define height (manifest-ref 'dynamic-font-cell-asset atlas "height" source))
    (define channels (manifest-ref 'dynamic-font-cell-asset atlas "channels" source))
    (unless (and (= width 256) (= height 256) (= channels 1) (= (file-size atlas-source) (* width height)))
      (raise-syntax-error 'dynamic-font-cell-asset "tabular-body R8 atlas geometry or length is invalid" source))
    (define glyphs (ref "glyphs"))
    (define glyph-count (ref "glyph_count"))
    (define expected-characters " 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    (unless (and (= glyph-count 37) (list? glyphs) (= (length glyphs) glyph-count)
                 (equal? (map (lambda (glyph) (manifest-ref 'dynamic-font-cell-asset glyph "glyph_id" source)) glyphs) (range 37))
                 (equal? (apply string-append (map (lambda (glyph) (manifest-ref 'dynamic-font-cell-asset glyph "character" source)) glyphs)) expected-characters))
      (raise-syntax-error 'dynamic-font-cell-asset "manifest must expose exactly the 37 dense TABULAR_BODY_V1 glyphs" source))
    (define compiled-glyphs
      (for/list ([glyph (in-list glyphs)])
        (define glyph-id (manifest-ref 'dynamic-font-cell-asset glyph "glyph_id" source))
        (define codepoint (manifest-ref 'dynamic-font-cell-asset glyph "codepoint" source))
        (define character (manifest-ref 'dynamic-font-cell-asset glyph "character" source))
        (define x (manifest-ref 'dynamic-font-cell-asset glyph "x" source))
        (define y (manifest-ref 'dynamic-font-cell-asset glyph "y" source))
        (define glyph-width (manifest-ref 'dynamic-font-cell-asset glyph "width" source))
        (define glyph-height (manifest-ref 'dynamic-font-cell-asset glyph "height" source))
        (define advance (manifest-ref 'dynamic-font-cell-asset glyph "advance" source))
        (define bearing-x (manifest-ref 'dynamic-font-cell-asset glyph "bearing_x" source))
        (define bearing-y (manifest-ref 'dynamic-font-cell-asset glyph "bearing_y" source))
        (unless (and (= advance 10.0) (hash-has-key? glyph 'source_advance)
                     (exact-nonnegative-integer? x) (exact-nonnegative-integer? y)
                     (exact-positive-integer? glyph-width) (exact-positive-integer? glyph-height)
                     (<= (+ x glyph-width) width) (<= (+ y glyph-height) height))
          (raise-syntax-error 'dynamic-font-cell-asset "tabular-body glyph UV/advance violates fixed-cell proof" source))
        (c-font-glyph glyph-id codepoint character x y glyph-width glyph-height advance bearing-x bearing-y)))
    (define font-sha (ref "font_sha256"))
    (define atlas-sha (ref "atlas_sha256"))
    (unless (and (regexp-match? #px"^[0-9a-f]{64}$" font-sha)
                 (regexp-match? #px"^[0-9a-f]{64}$" atlas-sha))
      (raise-syntax-error 'dynamic-font-cell-asset "tabular-body font/atlas SHA-256 fields must be lowercase digests" source))
    (c-dynamic-font-cell-asset face-id (c-font-asset-spec-manifest-path spec) (c-font-asset-spec-atlas-path spec)
                               font-sha atlas-sha width height channels "tabular-body-v1" "fixed-tabular" 10.0 compiled-glyphs source))

  (define (dynamic-font-cell-plan->datum asset virtual-list-plans placements)
    (if (not asset)
        '#f
        (let* ([placement-by-slot (for/hash ([placement (in-list placements)])
                                    (values (c-glyph-placement-slot placement) placement))]
               [tables
                (for/list ([list-plan (in-list virtual-list-plans)]
                           #:when (let ([table (c-virtual-list-plan-data-register-table list-plan)])
                                    (and table (equal? (hash-ref table 'font-face #f)
                                                       (c-dynamic-font-cell-asset-face-id asset)))))
                  (define table (c-virtual-list-plan-data-register-table list-plan))
                  (define slots (sort (append-map values (c-virtual-list-plan-row-glyph-slots list-plan)) <))
                  (define placements-for-table
                    (for/list ([slot (in-list slots)])
                      (hash-ref placement-by-slot slot
                                (lambda () (raise-syntax-error 'dynamic-font-cell-asset
                                                               "virtual-list row slot lacks a glyph placement"
                                                               (c-dynamic-font-cell-asset-source asset))))))
                  (unless (and (= (length slots) (* (hash-ref table 'register-width)
                                                    (c-virtual-list-plan-physical-slots list-plan)))
                               (for/and ([placement (in-list placements-for-table)])
                                 (and (= (c-glyph-placement-atlas-page placement) 3)
                                      (c-glyph-placement-dynamic? placement)
                                      (equal? (c-glyph-placement-face-id placement)
                                              (c-dynamic-font-cell-asset-face-id asset))
                                      (= (c-glyph-placement-advance placement) 10.0))))
                    (raise-syntax-error 'dynamic-font-cell-asset
                                        "page-3 placements disagree with fixed data-register cell proof"
                                        (c-dynamic-font-cell-asset-source asset)))
                  (hash 'table_id (symbol->string (hash-ref table 'id))
                        'list_id (symbol->string (c-virtual-list-plan-id list-plan))
                        'register_width (hash-ref table 'register-width)
                        'physical_slots (c-virtual-list-plan-physical-slots list-plan)
                        'placement_slots slots
                        'glyph_word_offsets (map c-glyph-placement-glyph-word-offset placements-for-table)
                        'cell_uv (map c-glyph-placement-atlas-uv placements-for-table)
                        'cell_advance (map c-glyph-placement-advance placements-for-table)
                        'tile_ids (c-virtual-list-plan-visible-tile-ids list-plan)
                        'packet_worklist_index 2))])
          (unless (pair? tables)
            (raise-syntax-error 'dynamic-font-cell-asset "declared page-3 asset is not referenced by any compact data-register-table" (c-dynamic-font-cell-asset-source asset)))
          `(dynamic-font-cell-plan
            ,(c-dynamic-font-cell-asset-face-id asset)
            ,(c-dynamic-font-cell-asset-manifest-path asset)
            ,(c-dynamic-font-cell-asset-atlas-path asset)
            ,(c-dynamic-font-cell-asset-font-sha256 asset)
            ,(c-dynamic-font-cell-asset-atlas-sha256 asset)
            ,(c-dynamic-font-cell-asset-atlas-width asset)
            ,(c-dynamic-font-cell-asset-atlas-height asset)
            ,(c-dynamic-font-cell-asset-atlas-channels asset)
            ,(c-dynamic-font-cell-asset-coverage-policy asset)
            ,(c-dynamic-font-cell-asset-advance-policy asset)
            ,(c-dynamic-font-cell-asset-fixed-advance asset)
            0 37 ',tables))))

  (define (font-asset-plan->datum plan)
    `(font-asset-plan ,(c-font-asset-plan-face-id plan)
                      ,(c-font-asset-plan-manifest-path plan)
                      ,(c-font-asset-plan-atlas-path plan)
                      ,(c-font-asset-plan-font-sha256 plan)
                      ,(c-font-asset-plan-atlas-sha256 plan)
                      ,(c-font-asset-plan-atlas-width plan)
                      ,(c-font-asset-plan-atlas-height plan)
                      ,(c-font-asset-plan-atlas-channels plan)
                      ,(c-font-asset-plan-pixel-size plan)
                      ,(c-font-asset-plan-line-height plan)
                      ,(c-font-asset-plan-glyph-domain-first plan)
                      ,(c-font-asset-plan-glyph-domain-count plan)
                      ,(c-font-asset-plan-atlas-page plan)
                      ,(c-font-asset-plan-activation plan)))

  (define (font-asset-plans->datum plans)
    `(list ,@(map font-asset-plan->datum plans)))

  (define (parse-log-browser-forms forms)
    (for/list ([form (in-list forms)])
      (syntax-parse form
        #:datum-literals (log-browser)
        [(log-browser #:id id:id #:for list-id:id #:detail detail-id:id
                      #:append ((index value) ...+))
         (define indices (map syntax-e (syntax->list #'(index ...))))
         (define values (map (lambda (item) (component-literal-string 'log-browser item))
                             (syntax->list #'(value ...))))
         (unless (andmap exact-nonnegative-integer? indices)
           (raise-syntax-error 'log-browser "append indices must be non-negative integer literals" form))
         (unless (= (length indices) (length (remove-duplicates indices)))
           (raise-syntax-error 'log-browser "append indices must be unique" form))
         (c-log-browser-spec (syntax-e #'id) (syntax-e #'list-id) (syntax-e #'detail-id)
                            (map cons indices values) form)]
        [_ (raise-syntax-error 'log-browser "expected (log-browser #:id id #:for list #:detail text-id #:append ((index UPPERCASE_RECORD) ...+))" form)])))

  (define (compile-log-browser-plans specs root layouts glyph-placements virtual-list-plans render-schedules)
    (define list-by-id (for/hash ([plan (in-list virtual-list-plans)])
                         (values (c-virtual-list-plan-id plan) plan)))
    (define layout-by-id (for/hash ([layout (in-list layouts)])
                           (values (c-layout-id layout) layout)))
    (define node-by-id (for/hash ([node (in-list (walk-nodes root))])
                          (values (c-node-id node) node)))
    (define schedule (and (pair? render-schedules) (car render-schedules)))
    (for/list ([spec (in-list specs)])
      (define list-plan
        (hash-ref list-by-id (c-log-browser-spec-list-id spec)
                  (lambda () (raise-syntax-error 'log-browser "#:for must reference a virtual-list in the same root" (c-log-browser-spec-source spec)))))
      (define table (c-virtual-list-plan-data-register-table list-plan))
      (unless table
        (raise-syntax-error 'log-browser "requires compact data-register-table virtual-list" (c-log-browser-spec-source spec)))
      (define capacity (c-virtual-list-plan-logical-capacity list-plan))
      (define width (hash-ref table 'register-width))
      (define updates (sort (c-log-browser-spec-append-updates spec) < #:key car))
      (define indices (map car updates))
      (unless (and (= (last indices) (sub1 capacity))
                   (equal? indices (range (first indices) (add1 (last indices)))))
        (raise-syntax-error 'log-browser "append records must form a contiguous tail interval ending at logical_capacity-1" (c-log-browser-spec-source spec)))
      (for ([entry (in-list updates)])
        (define value (cdr entry))
        (unless (and (<= (string-length value) width)
                     (for/and ([ch (in-string value)]) (or (char=? ch #\space) (char-numeric? ch) (char<=? #\A ch #\Z))))
          (raise-syntax-error 'log-browser "append records must be fixed-width uppercase ASCII" (c-log-browser-spec-source spec))))
      (define detail-id (c-log-browser-spec-detail-id spec))
      (define detail-layout (hash-ref layout-by-id detail-id
                                      (lambda () (raise-syntax-error 'log-browser "#:detail must reference a layout node" (c-log-browser-spec-source spec)))))
      (define detail-node (hash-ref node-by-id detail-id))
      (unless (eq? (c-node-tag detail-node) 'text)
        (raise-syntax-error 'log-browser "#:detail must reference a text node" (c-log-browser-spec-source spec)))
      (define detail-placements (filter (lambda (placement) (eq? (c-glyph-placement-node-id placement) detail-id)) glyph-placements))
      (unless (pair? detail-placements)
        (raise-syntax-error 'log-browser "detail text requires a fixed glyph placement range" (c-log-browser-spec-source spec)))
      (define detail-tile-ids
        (if schedule
            (for/list ([tile (in-list (c-render-schedule-tiles schedule))] [tile-id (in-naturals)]
                       #:when (rect-intersection (layout-rect detail-layout) (tile-rect tile))) tile-id)
            '()))
      (unless (pair? detail-tile-ids)
        (raise-syntax-error 'log-browser "detail panel must intersect a compiled render tile" (c-log-browser-spec-source spec)))
      ;; A layout rect may extend past a clipped tile. Export only the glyph cells contained in
      ;; the already-compiled packet subranges; the host must never patch clipped placements.
      (define detail-covered-slots
        (for*/set ([tile-id (in-list detail-tile-ids)]
                   [range (in-list (c-render-tile-glyph-packet-ranges (list-ref (c-render-schedule-tiles schedule) tile-id)))]
                   [slot (in-range (c-glyph-packet-range-first-placement range)
                                   (+ (c-glyph-packet-range-first-placement range)
                                      (c-glyph-packet-range-placement-count range)))])
          slot))
      (define detail-offsets
        (for/list ([placement (in-list detail-placements)]
                   #:when (set-member? detail-covered-slots (c-glyph-placement-slot placement)))
          (c-glyph-placement-glyph-byte-offset placement)))
      (unless (and (pair? detail-offsets)
                   (equal? detail-offsets (sort detail-offsets <))
                   (andmap (lambda (offset) (= (modulo offset 4) 0)) detail-offsets))
        (raise-syntax-error 'log-browser "detail glyph offsets must be tile-covered, strictly increasing and 4-byte aligned" (c-log-browser-spec-source spec)))
      (c-log-browser-plan (c-log-browser-spec-id spec) (c-log-browser-spec-list-id spec)
                          (string->symbol (format "~a-append" (c-log-browser-spec-id spec))) updates detail-id detail-offsets detail-tile-ids
                          (map (lambda (offset) (+ offset 16)) (c-virtual-list-plan-row-layout-offsets list-plan))
(list (hash 'name 'INFO 'color '(0.025 0.040 0.065 1.0))
                                  ;; Row quads are opaque in this renderer, so semantic tints use
                                  ;; low luminance rather than misleading alpha values.
                                  (hash 'name 'WARN 'color '(0.055 0.035 0.010 1.0))
                                  (hash 'name 'ERROR 'color '(0.070 0.015 0.026 1.0))
                                  (hash 'name 'DEBUG 'color '(0.035 0.025 0.060 1.0)))
                          2)))

  (define (log-browser-plan->datum plan)
    `(log-browser-plan ',(c-log-browser-plan-id plan)
                       ',(c-log-browser-plan-list-id plan)
                       ',(c-log-browser-plan-append-batch-id plan)
                       ',(map car (c-log-browser-plan-append-updates plan))
                       ',(c-log-browser-plan-append-updates plan)
                       ',(c-log-browser-plan-detail-node-id plan)
                       ',(c-log-browser-plan-detail-glyph-offsets plan)
                       ',(c-log-browser-plan-detail-tile-ids plan)
                       ',(c-log-browser-plan-row-color-offsets plan)
                       ',(c-log-browser-plan-levels plan)
                       ,(c-log-browser-plan-packet-worklist-index plan)))

  (define (log-browser-plans->datum plans)
    `(list ,@(map log-browser-plan->datum plans)))

  (define (compile-list-navigation-plans specs virtual-list-plans scrollbar-plans)
    (define list-by-id (for/hash ([plan (in-list virtual-list-plans)])
                         (values (c-virtual-list-plan-id plan) plan)))
    (define scrollbar-by-id (for/hash ([plan (in-list scrollbar-plans)])
                              (values (c-scrollbar-plan-id plan) plan)))
    (for/list ([spec (in-list specs)])
      (define list-plan
        (hash-ref list-by-id (c-list-navigation-spec-list-id spec)
                  (lambda () (raise-syntax-error 'list-navigation "#:for must refer to a virtual-list in the same static root" (c-list-navigation-spec-source spec)))))
      (define scrollbar
        (hash-ref scrollbar-by-id (c-list-navigation-spec-scrollbar-id spec)
                  (lambda () (raise-syntax-error 'list-navigation "#:scrollbar must refer to a scrollbar in the same static root" (c-list-navigation-spec-source spec)))))
      (unless (eq? (c-scrollbar-plan-list-id scrollbar) (c-virtual-list-plan-id list-plan))
        (raise-syntax-error 'list-navigation "#:for and #:scrollbar must bind the same virtual-list" (c-list-navigation-spec-source spec)))
      (unless (c-virtual-list-plan-data-register-table list-plan)
        (raise-syntax-error 'list-navigation "v1 requires a compact data-register virtual-list" (c-list-navigation-spec-source spec)))
      (define page-step (c-virtual-list-plan-visible-rows list-plan))
      (define max-viewport (- (c-virtual-list-plan-logical-capacity list-plan) page-step))
      (unless (> max-viewport 0)
        (raise-syntax-error 'list-navigation "requires logical-capacity > visible-rows" (c-list-navigation-spec-source spec)))
      (c-list-navigation-plan (c-list-navigation-spec-id spec)
                              (c-list-navigation-spec-list-id spec)
                              (c-list-navigation-spec-scrollbar-id spec)
                              page-step max-viewport
                              '((page-up subtract-step) (page-down add-step-clamp) (home set-zero) (end set-max))
                              (c-scrollbar-plan-tile-ids scrollbar)
                              (c-scrollbar-plan-packet-worklist-index scrollbar)
                              'logical-mod-physical-slots)))

  (define (list-navigation-plan->datum plan)
    `(list-navigation-plan ',(c-list-navigation-plan-id plan)
                           ',(c-list-navigation-plan-list-id plan)
                           ',(c-list-navigation-plan-scrollbar-id plan)
                           ,(c-list-navigation-plan-page-step plan)
                           ,(c-list-navigation-plan-max-viewport plan)
                           ',(c-list-navigation-plan-transitions plan)
                           ',(c-list-navigation-plan-tile-ids plan)
                           ,(c-list-navigation-plan-packet-worklist-index plan)
                           ',(c-list-navigation-plan-physical-slot-rule plan)))

  (define (list-navigation-plans->datum plans)
    `(list ,@(map list-navigation-plan->datum plans)))

  (define (virtual-list-plan->datum plan)
    `(virtual-list-plan ',(c-virtual-list-plan-id plan)
                        ,(c-virtual-list-plan-capacity plan)
                        ,(c-virtual-list-plan-logical-capacity plan)
                        ,(c-virtual-list-plan-physical-slots plan)
                        ,(c-virtual-list-plan-recycling? plan)
                        ',(c-virtual-list-plan-logical-data-ids plan)
                        ',(c-virtual-list-plan-logical-labels plan)
                        ',(c-virtual-list-plan-initial-ring-slots plan)
                        ',(c-virtual-list-plan-data-register-table plan)
                        ',(c-virtual-list-plan-data-update-batches plan)
                        ,(c-virtual-list-plan-visible-rows plan)
                        ,(c-virtual-list-plan-row-height plan)
                        ,(c-virtual-list-plan-viewport-height plan)
                        ',(c-virtual-list-plan-row-ids plan)
                        ',(c-virtual-list-plan-row-layout-offsets plan)
                        ',(c-virtual-list-plan-row-instance-offsets plan)
                        ',(c-virtual-list-plan-row-glyph-slots plan)
                        ',(c-virtual-list-plan-row-draw-ranges plan)
                        ',(c-virtual-list-plan-row-glyph-subranges plan)
                        ',(c-virtual-list-plan-visible-tile-ids plan)
                        (list ,@(map virtual-scroll-transition->datum
                                      (c-virtual-list-plan-scroll-transitions plan)))))

  (define (virtual-list-plans->datum plans)
    `(list ,@(map virtual-list-plan->datum plans)))

  ;; Resolve the parser-preserved on-activate symbol only after action slots, action
  ;; tile plans, task worklists, and selected coalesced strategies are immutable.
  ;; The result is a runtime datum with no action-name lookup on the hot path.
  (define (compile-row-activation-plans root action-plans action-indexes schedule batches)
    (define action-by-id
      (for/hash ([plan (in-list action-plans)])
        (values (c-action-plan-id plan) plan)))
    (define task-by-id
      (for/hash ([task (in-list schedule)])
        (values (c-frame-task-id task) task)))
    (for/list ([node (in-list (filter (lambda (candidate) (eq? (c-node-tag candidate) 'virtual-list))
                                      (walk-nodes root)))]
               #:when (hash-ref (c-node-props node) 'on-activate #f))
      (define props (c-node-props node))
      (define action-id (hash-ref props 'on-activate))
      (define action-plan
        (or (hash-ref action-by-id action-id #f)
            (raise-syntax-error 'on-activate
                                (format "unknown Action ID ~a" action-id)
                                (c-node-source node))))
      (define action-slot
        (or (hash-ref action-indexes action-id #f)
            (raise-syntax-error 'on-activate
                                (format "Action ~a has no canonical Action Slot" action-id)
                                (c-node-source node))))
      (define activate-batch
        (or (for/first ([batch (in-list batches)]
                        #:when (and (regexp-match? #rx"^coalesced-activate-" (symbol->string (c-coalesced-batch-id batch)))
                                    (member action-id (c-coalesced-batch-task-ids batch))))
              batch)
            (raise-syntax-error 'on-activate
                                (format "Action ~a has no compiler activate batch" action-id)
                                (c-node-source node))))
      (define task
        (or (hash-ref task-by-id action-id #f)
            (raise-syntax-error 'on-activate
                                (format "Action ~a has no scheduled frame task" action-id)
                                (c-node-source node))))
      (define tile-mask
        (for/fold ([mask 0]) ([tile-id (in-list (c-action-plan-tile-ids action-plan))])
          (bitwise-ior mask (arithmetic-shift 1 tile-id))))
      (unless (and (eq? (c-coalesced-batch-strategy-id activate-batch) 'coalesced)
                   (= (c-frame-task-packet-worklist-index task) 2))
        (raise-syntax-error 'on-activate
                            "row activation requires a coalesced no-packets Action task"
                            (c-node-source node)))
      `(row-activation-plan ',(c-node-id node)
                            ',action-id
                            ,action-slot
                            ',(c-coalesced-batch-id activate-batch)
                            ,tile-mask
                            ,(c-frame-task-packet-worklist-index task)
                            ',(c-coalesced-batch-strategy-id activate-batch)
                            'logical-mod-physical-slots)))

  (define (row-activation-plans->datum plans)
    `(list ,@plans))

  (define (event-binding->datum event)
    `(event-binding ,(c-event-slot event)
                    ',(c-event-node-id event)
                    ',(c-event-action event)
                    ',(c-event-action-index event)
                    ',(c-event-transaction-op event)
                    ',(c-event-transaction-index event)
                    ,(c-event-x event) ,(c-event-y event)
                    ,(c-event-width event) ,(c-event-height event)
                    ,(c-event-z-index event)
                    ,(c-event-instance-offset event)
                    ',(c-event-base-color event)
                    ',(c-event-hover-color event)
                    ',(c-event-pressed-color event)
                    ',(c-event-base-pos event)
                    ',(c-event-pressed-pos event)))

  (define (event-map->datum events)
    `(list ,@(map event-binding->datum events)))

  (define (animation-track->datum animation)
    (define event (c-animation-event animation))
    `(animation-track ',(c-animation-id animation)
                      ',(c-event-node-id event)
                      ,(c-event-instance-offset event)
                      ,(c-event-instance-offset event)
                      ,(+ (c-event-instance-offset event) 16)
                      ,(c-animation-duration-ms animation)
                      ',(c-animation-easing animation)
                      ',(c-event-pressed-pos event)
                      ',(c-event-base-pos event)
                      ',(c-event-pressed-color event)
                      ',(c-event-base-color event)
                      (damage-region 'rect
                                     ',(c-event-node-id event)
                                     ,(c-event-x event) ,(c-event-y event)
                                     ,(c-event-width event) ,(c-event-height event)
                                     ,(c-event-instance-offset event))))

  (define (animation-tracks->datum tracks)
    `(list ,@(map animation-track->datum tracks)))

  (define (c-focus-entry->datum entry)
    `(focus-entry ,(c-focus-entry-slot entry)
                  ',(c-focus-entry-node-id entry)
                  ',(c-focus-entry-state entry)
                  ,(c-focus-entry-state-index entry)
                  ,(c-focus-entry-tab-index entry)
                  ,(c-focus-entry-next-slot entry)
                  ,(c-focus-entry-previous-slot entry)
                  ',(c-focus-entry-tile-ids entry)
                  ,(c-focus-entry-instance-offset entry)))

  (define (focus-graph->datum graph)
    `(focus-graph (list ,@(map c-focus-entry->datum (c-focus-graph-entries graph)))
                  ,(c-focus-graph-initial-slot graph)))

  (define (c-digit-register->datum register)
    `(digit-register ,(c-digit-register-radix register)
                     ,(c-digit-register-max-digits register)
                     ,(c-digit-register-initial-value register)
                     ,(c-digit-register-reset-value register)
                     ,(c-digit-register-maximum-value register)))

  (define (c-ascii-text-register->datum register)
    `(ascii-text-register ',(c-ascii-text-register-charset register)
                          ,(c-ascii-text-register-max-chars register)
                          ,(c-ascii-text-register-initial-packed register)
                          ,(c-ascii-text-register-reset-packed register)
                          ,(c-ascii-text-register-atlas-page register)))

  (define (c-keyboard-field->datum field)
    `(keyboard-field ,(c-keyboard-field-focus-slot field)
                     ',(c-keyboard-field-node-id field)
                     ',(c-keyboard-field-state field)
                     ,(c-keyboard-field-state-index field)
                     ,(c-keyboard-field-max-chars field)
                     ',(c-keyboard-field-charset field)
                     ',(c-keyboard-field-glyph-id-offsets field)
                     ',(c-keyboard-field-tile-ids field)
                     ,(if (c-keyboard-field-digit-register field)
                          (c-digit-register->datum (c-keyboard-field-digit-register field))
                          #f)
                     ,(if (c-keyboard-field-ascii-text-register field)
                          (c-ascii-text-register->datum (c-keyboard-field-ascii-text-register field))
                          #f)))

  (define (c-keyboard-transition->datum transition)
    `(keyboard-transition ,(c-keyboard-transition-focus-slot transition)
                          ',(c-keyboard-transition-key transition)
                          ',(c-keyboard-transition-kind transition)
                          ,(c-keyboard-transition-glyph-id transition)
                          ',(c-keyboard-transition-cursor-op transition)
                          ',(c-keyboard-transition-tile-ids transition)
                          ',(c-keyboard-transition-register-op transition)
                          ,(c-keyboard-transition-register-radix transition)
                          ,(c-keyboard-transition-register-operand transition)))

  (define (keyboard-map->datum kmap)
    `(keyboard-map (list ,@(map c-keyboard-field->datum (c-keyboard-map-fields kmap)))
                   (list ,@(map c-keyboard-transition->datum (c-keyboard-map-transitions kmap)))) )

  (define (c-keyboard-command-transition->datum transition)
    `(keyboard-command-transition ,(c-keyboard-command-transition-focus-slot transition)
                                  ',(c-keyboard-command-transition-key transition)
                                  ',(c-keyboard-command-transition-kind transition)
                                  ',(c-keyboard-command-transition-action transition)
                                  ',(c-keyboard-command-transition-action-index transition)
                                  ',(c-keyboard-command-transition-transaction-index transition)
                                  ',(c-keyboard-command-transition-target-state transition)
                                  ',(c-keyboard-command-transition-target-state-index transition)
                                  ',(c-keyboard-command-transition-tile-ids transition)))

  (define (keyboard-command-map->datum command-map)
    `(keyboard-command-map (list ,@(map c-keyboard-command-transition->datum
                                         (c-keyboard-command-map-transitions command-map)))))

  (define (frame-task->datum task)
    `(frame-task ',(c-frame-task-id task)
                 ',(c-frame-task-kind task)
                 ,(c-frame-task-priority task)
                 ',(c-frame-task-writes task)
                 ',(c-frame-task-tile-ids task)
                 ,(c-frame-task-packet-worklist-index task)
                 ',(c-frame-task-packet-worklist-indices task)))

  (define (frame-schedule->datum tasks)
    `(list ,@(map frame-task->datum tasks)))

  (define (conflict-edge->datum conflict)
    `(conflict-edge ',(c-conflict-left conflict)
                    ',(c-conflict-right conflict)
                    ',(c-conflict-winner conflict)
                    ',(c-conflict-overlaps conflict)))

  (define (conflict-graph->datum conflicts)
    `(list ,@(map conflict-edge->datum conflicts)))

  (define (c-coalesced-write->datum write)
    `(frame-coalesced-write ',(c-coalesced-write-task-id write)
                            ,(c-coalesced-write-offset write)
                            ,(c-coalesced-write-byte-length write)))

  (define (c-coalesced-elimination->datum eliminated)
    `(frame-coalesced-elimination ',(c-coalesced-elimination-task-id eliminated)
                                  ,(c-coalesced-elimination-offset eliminated)
                                  ,(c-coalesced-elimination-byte-length eliminated)
                                  ',(c-coalesced-elimination-winner eliminated)))

  (define (transaction-task-index task-id)
    (define match (regexp-match #rx"^transaction-([0-9]+)$" (symbol->string task-id)))
    (and match (string->number (second match))))

  (define (transient-task-index-by-id schedule action-indexes)
    (for/hash ([task (in-list (sort (filter (lambda (task)
                                               (and (not (hash-has-key? action-indexes (c-frame-task-id task)))
                                                    (not (transaction-task-index (c-frame-task-id task)))))
                                             schedule)
                                      symbol<? #:key c-frame-task-id))]
               [index (in-naturals)])
      (values (c-frame-task-id task) index)))

  (define (batch-task-ref->datum task-id action-indexes transient-indexes)
    (cond [(hash-has-key? action-indexes task-id)
           `(batch-task-ref 'action ,(hash-ref action-indexes task-id) ',task-id)]
          [(transaction-task-index task-id)
           `(batch-task-ref 'transaction ,(transaction-task-index task-id) ',task-id)]
          [else `(batch-task-ref 'transient ,(hash-ref transient-indexes task-id
                                                        (lambda () (error 'batch-task-ref "unknown task ~a" task-id)))
                                 ',task-id)]))

  (define (c-coalesced-batch->datum batch action-indexes transient-indexes)
    `(frame-coalesced-batch ',(c-coalesced-batch-id batch)
                            ',(c-coalesced-batch-task-ids batch)
                            ',(c-coalesced-batch-execution-order batch)
                            (list ,@(map (lambda (task-id)
                                           (batch-task-ref->datum task-id action-indexes transient-indexes))
                                         (c-coalesced-batch-execution-order batch)))
                            (list ,@(map c-coalesced-write->datum (c-coalesced-batch-winner-writes batch)))
                            (list ,@(map c-coalesced-elimination->datum (c-coalesced-batch-eliminated-writes batch)))
                            ',(c-coalesced-batch-merged-tile-ids batch)
                            (list ,@(map conflict-edge->datum (c-coalesced-batch-conflict-edges batch)))
                            ',(c-coalesced-batch-strategy-id batch)
                            ',(c-coalesced-batch-candidate-costs batch)
                            ',(c-coalesced-batch-selection-proof batch)
                            ,(c-coalesced-batch-composite-worklist-index batch)
                            ',(c-coalesced-batch-composite-worklist-member-indices batch)
                            ',(c-coalesced-batch-composite-worklist-packet-indices batch)
                            ',(c-coalesced-batch-fusion-baseline-requests batch)))

  (define (frame-coalesced-batches->datum batches action-indexes schedule)
    (define transient-indexes (transient-task-index-by-id schedule action-indexes))
    `(list ,@(map (lambda (batch)
                    (c-coalesced-batch->datum batch action-indexes transient-indexes))
                  batches)))

  (define (render-tile->datum tile)
    `(render-tile ,(c-render-tile-x tile) ,(c-render-tile-y tile)
                  ,(c-render-tile-width tile) ,(c-render-tile-height tile)
                  ',(c-render-tile-nodes tile)
                  (list ,@(map c-draw-range->datum (c-render-tile-draw-ranges tile)))
                  (list ,@(map c-glyph-packet-range->datum (c-render-tile-glyph-packet-ranges tile)))
                  ',(c-render-tile-fallback-reason tile)
                  ',(c-render-tile-selected-strategy tile)
                  (hash ,@(append-map (lambda (pair) (list `(quote ,(car pair)) (cdr pair)))
                                      (hash->list (c-render-tile-candidate-costs tile))))))

  (define (render-schedule->datum schedule)
    `(render-schedule ',(c-render-schedule-id schedule)
                      ',(c-render-schedule-task-ids schedule)
                      (list ,@(map render-tile->datum (c-render-schedule-tiles schedule)))
                      ,(c-render-schedule-coverage schedule)
                      ,(c-render-schedule-full-redraw? schedule)
                      ,(c-render-schedule-profile-id schedule)))

  (define (render-schedules->datum schedules)
    `(list ,@(map render-schedule->datum schedules)))

  (define (glyph-placement->datum placement)
    `(glyph-placement ,(c-glyph-placement-slot placement)
                      ',(c-glyph-placement-node-id placement)
                      ,(c-glyph-placement-glyph-index placement)
                      ,(c-glyph-placement-glyph-id placement)
                      ,(c-glyph-placement-atlas-page placement)
                      ,(c-glyph-placement-glyph-byte-offset placement)
                      ,(c-glyph-placement-glyph-word-offset placement)
                      ',(c-glyph-placement-ndc-pos placement)
                      ',(c-glyph-placement-ndc-size placement)
                      ',(c-glyph-placement-atlas-uv placement)
                      ,(c-glyph-placement-advance placement)
                      ,(c-glyph-placement-dynamic? placement)
                      ',(c-glyph-placement-state placement)
                      ',(c-glyph-placement-state-index placement)
                      ',(c-glyph-placement-clip-stack-id placement)
                      ',(c-glyph-placement-clip-rect placement)
                      ,(c-glyph-placement-z-layer placement)
                      ',(c-glyph-placement-batch-key placement)
                      ,(c-glyph-placement-face-id placement)))

  (define (glyph-placement-plan->datum placements)
    `(list ,@(map glyph-placement->datum placements)))

  (define (glyph-packet->datum packet)
    `(glyph-draw-packet ',(c-glyph-packet-id packet)
                        ,(c-glyph-packet-atlas-page packet)
                        ,(c-glyph-packet-first-placement packet)
                        ,(c-glyph-packet-placement-count packet)
                        ,(c-glyph-packet-first-glyph-byte-offset packet)
                        ,(c-glyph-packet-glyph-byte-length packet)
                        ',(c-glyph-packet-nodes packet)
                        ',(c-glyph-packet-bounds packet)
                        ',(c-glyph-packet-clip-stack-id packet)
                        ',(c-glyph-packet-clip-rect packet)
                        ,(c-glyph-packet-z-layer packet)
                        ',(c-glyph-packet-batch-key packet)
                        ,(c-glyph-packet-dynamic? packet)))

  (define (glyph-packets->datum packets)
    `(list ,@(map glyph-packet->datum packets)))

  (define (packet-worklists->datum worklists)
    `(list ,@(for/list ([worklist (in-list worklists)])
                `(packet-worklist ,(c-packet-worklist-index worklist)
                                  ',(c-packet-worklist-id worklist)
                                  (list ,@(c-packet-worklist-packet-indices worklist))))))

  (define (packet-activity-contract->datum contract)
    `(packet-activity-contract ,(c-packet-activity-contract-packet-count contract)
                               ,(c-packet-activity-contract-workgroup-size contract)
                               ',(c-packet-activity-contract-scalar-entry contract)
                               ',(c-packet-activity-contract-subgroup-entry contract)
                               ,(c-packet-activity-contract-differential-required? contract)))

  (define (subgroup-packets->datum packets)
    `(list ,@(for/list ([packet (in-list packets)])
                `(subgroup-packet ,(c-subgroup-packet-index packet)
                                  ',(c-subgroup-packet-packet-id packet)
                                  ,(c-subgroup-packet-packet-index packet)
                                  ,(c-subgroup-packet-first-placement packet)
                                  ,(c-subgroup-packet-lane-count packet)
                                  ,(c-subgroup-packet-subgroup-width packet)
                                  ,(c-subgroup-packet-active-lane-mask packet)
                                  ,(c-subgroup-packet-activity-word-offset packet)
                                  ,(c-subgroup-packet-indirect-byte-offset packet)
                                  ,(c-subgroup-packet-dynamic? packet)))))

  (define (state-table->datum states)
    `(hash ,@(append-map
              (lambda (state) (list `(quote ,(c-state-id state)) (c-state-initial state)))
              states)))

  (define (state-slots->datum states)
    `(list ,@(for/list ([state (in-list (canonical-states states))] [index (in-naturals)])
                `(state-slot ,index ',(c-state-id state) ,(c-state-initial state)))))

  (define (action-slots->datum actions)
    `(list ,@(for/list ([action (in-list (canonical-actions actions))] [index (in-naturals)])
                `(action-slot ,index ',(c-action-id action)))))

  (define (transaction-plans->datum plans)
    `(list ,@(for/list ([plan (in-list plans)])
                `(transaction-plan ,(c-transaction-plan-index plan)
                                   ',(c-transaction-plan-id plan)
                                   ',(c-transaction-plan-field-slots plan)
                                   ',(c-transaction-plan-state-indices plan)
                                   ',(c-transaction-plan-tile-ids plan)))))

  (define (command-matchers->datum matchers)
    `(list ,@(for/list ([matcher (in-list matchers)])
                `(command-matcher ',(c-command-matcher-field matcher)
                                  ,(c-command-matcher-focus-slot matcher)
                                  ,(c-command-matcher-literal matcher)
                                  ,(c-command-matcher-length matcher)
                                  ,(c-command-matcher-packed matcher)
                                  ',(c-command-matcher-action matcher)
                                  ,(c-command-matcher-action-index matcher)
                                  ',(c-command-matcher-tile-ids matcher)))))

  (define (action-plan->datum plan state-indexes)
    (define action (c-action-plan-action plan))
    `(action-plan ',(c-action-plan-id plan) ,(c-action-plan-action-index plan)
                  (list (state-write ',(c-action-state action)
                                     ,(hash-ref state-indexes (c-action-state action))
                                     ',(c-action-op action)
                                     ,(c-action-value action)))
                  (list
                   ,@(map (lambda (binding)
                            `(gpu-update 'text-run
                                         ',(c-binding-node-id binding)
                                         ',(c-binding-state binding)
                                         ,(hash-ref state-indexes (c-binding-state binding))
                                         ,(c-binding-offset binding)
                                         ,(c-binding-byte-length binding)
                                         ,(c-binding-glyph-count binding)
                                         ',(for/list ([index (in-range (c-binding-glyph-count binding))])
                                             (+ (c-binding-offset binding) (* index glyph-instance-bytes)))))
                          (c-action-plan-text-updates plan)))
                  (list
                   ,@(map (lambda (binding)
                            (define layout (c-instance-binding-layout binding))
                            ;; QuadInstance: pos[2] 位于 bytes 0..8，size.x 正好位于 byte 8。
                            (define size-x-offset (+ (c-layout-instance-offset layout) 8))
                            (define scale (/ (* 2.0 (/ (c-layout-width layout) (canvas-width)))
                                             (c-instance-binding-max-value binding)))
                            `(instance-update 'instance-patch
                                              ',(c-instance-binding-node-id binding)
                                              ',(c-instance-binding-state binding)
                                              ,(hash-ref state-indexes (c-instance-binding-state binding))
                                              ,size-x-offset 4 'size.x ,scale))
                          (c-action-plan-instance-updates plan)))
                  (list
                   ,@(map (lambda (layout)
                            `(damage-region 'rect
                                            ',(c-layout-id layout)
                                            ,(c-layout-x layout)
                                            ,(c-layout-y layout)
                                            ,(c-layout-width layout)
                                            ,(c-layout-height layout)
                                            ,(c-layout-instance-offset layout)))
                          (c-action-plan-damage plan)))
                  ',(c-action-plan-tile-ids plan)))

  (define (form-head-symbol form)
    (define forms (syntax->list form))
    (and (pair? forms) (syntax-e (car forms))))

  (define (datum-stx source datum)
    ;; 生成表达式必须保留语言实现模块的词法上下文；若直接使用用户模块
    ;; 的 syntax context，展开产物中的 ui-node/hash/action-plan 会变成未绑定标识符。
    (datum->syntax #'ui-node datum source source)))

;; ------------------------------ User macros ------------------------------

(define-syntax (ui stx)
  (syntax-parse stx
    [(_ root:expr)
     (define-values (root-node _) (parse-node #'root (set)))
     (define-values (total dynamic budget updates) (compile-scene root-node))
     (define layouts (compile-layout-plan root-node))
     (define rounded-surfaces (compile-rounded-surface-plan root-node layouts))
     (define shadow-surfaces (compile-shadow-surface-plan root-node layouts))
     (define-values (glyph-placements glyph-packets)
       (compile-glyph-placement-plan root-node '() layouts (hash)))
     (define subgroup-packets (compile-subgroup-packet-plan glyph-packets))
     (define packet-activity-contract (compile-packet-activity-contract subgroup-packets))
     (define base-packet-worklists (compile-packet-worklists subgroup-packets))
     (define events (compile-event-map root-node layouts (hash) (hash)))
     (define tracks (compile-animation-tracks events))
     (define schedule (compile-frame-schedule events tracks '()))
     (define conflicts (compile-conflict-graph schedule))
     (define coalesced-batches '())
     (define render-schedules (compile-render-schedules root-node layouts events tracks '() glyph-placements glyph-packets schedule))
     (define virtual-list-plans (compile-virtual-list-plans root-node layouts glyph-placements))
     (define scrollbar-plans (compile-scrollbar-plans root-node layouts virtual-list-plans render-schedules))
     (define list-navigation-plans '())
     (define focus-graph (compile-focus-graph root-node layouts render-schedules (hash)))
     (define keyboard-map (compile-keyboard-map root-node focus-graph (hash)))
     (define keyboard-command-map (compile-keyboard-command-map root-node focus-graph '() (hash) '()))
     (define packet-worklists (compile-task-packet-worklists base-packet-worklists subgroup-packets glyph-packets focus-graph '()))
     (with-syntax ([ROOT (datum-stx stx (node->datum root-node))]
                   [STATIC (datum-stx stx (- total dynamic))]
                   [DYNAMIC (datum-stx stx dynamic)]
                   [BUDGET (datum-stx stx `(quote ,budget))]
                   [STATE-SLOTS (datum-stx stx ''())]
                   [TRANSACTIONS (datum-stx stx ''())]
                   [COMMAND-MATCHERS (datum-stx stx ''())]
                   [UPDATES (datum-stx stx `(quote ,updates))]
                   [LAYOUT (datum-stx stx (layout-plan->datum layouts root-node '()))]
                   [GLYPH-PLACEMENTS (datum-stx stx (glyph-placement-plan->datum glyph-placements))]
                   [GLYPH-PACKETS (datum-stx stx (glyph-packets->datum glyph-packets))]
                   [SUBGROUP-PACKETS (datum-stx stx (subgroup-packets->datum subgroup-packets))]
                   [PACKET-ACTIVITY-CONTRACT (datum-stx stx (packet-activity-contract->datum packet-activity-contract))]
                   [PACKET-WORKLISTS (datum-stx stx (packet-worklists->datum packet-worklists))]
                   [EVENTS (datum-stx stx (event-map->datum events))]
                   [TRACKS (datum-stx stx (animation-tracks->datum tracks))]
                   [SCHEDULE (datum-stx stx (frame-schedule->datum schedule))]
                   [CONFLICTS (datum-stx stx (conflict-graph->datum conflicts))]
                   [BATCHES (datum-stx stx (frame-coalesced-batches->datum coalesced-batches (hash) schedule))]
                   [RENDER-SCHEDULES (datum-stx stx (render-schedules->datum render-schedules))]
                   [FOCUS-GRAPH (datum-stx stx (focus-graph->datum focus-graph))]
                   [KEYBOARD-MAP (datum-stx stx (keyboard-map->datum keyboard-map))]
                   [KEYBOARD-COMMAND-MAP (datum-stx stx (keyboard-command-map->datum keyboard-command-map))]
                   [VIRTUAL-LISTS (datum-stx stx (virtual-list-plans->datum virtual-list-plans))]
                   [SCROLLBARS (datum-stx stx (scrollbar-plans->datum scrollbar-plans))]
                   [LIST-NAVIGATIONS (datum-stx stx (list-navigation-plans->datum list-navigation-plans))]
                    [LOG-BROWSERS (datum-stx stx ''())]
                    [FONT-ASSETS (datum-stx stx ''())]
                    [DYNAMIC-FONT-CELL-PLAN (datum-stx stx '#f)]
                    [VISUAL-LANGUAGE (datum-stx stx '(visual-language-plan 'bench 640.0 360.0 16.0))]
                    [ROUNDED-SURFACES (datum-stx stx (rounded-surface-plan->datum rounded-surfaces))]
                    [SHADOW-SURFACES (datum-stx stx (shadow-surface-plan->datum shadow-surfaces))])
       #'(scene ROOT STATIC DYNAMIC BUDGET (hash) STATE-SLOTS '() '() TRANSACTIONS COMMAND-MATCHERS UPDATES LAYOUT GLYPH-PLACEMENTS GLYPH-PACKETS SUBGROUP-PACKETS PACKET-ACTIVITY-CONTRACT PACKET-WORKLISTS EVENTS TRACKS SCHEDULE CONFLICTS BATCHES RENDER-SCHEDULES FOCUS-GRAPH KEYBOARD-MAP KEYBOARD-COMMAND-MAP VIRTUAL-LISTS '() SCROLLBARS LIST-NAVIGATIONS LOG-BROWSERS FONT-ASSETS DYNAMIC-FONT-CELL-PLAN VISUAL-LANGUAGE ROUNDED-SURFACES SHADOW-SURFACES))]
    [(_ root:expr extra:expr ...)
     (raise-syntax-error 'ui "expects exactly one root layout node" stx)]))

(define-syntax (noir-app stx)
  (syntax-parse stx
    [(_ form:expr ...)
     (define forms (syntax->list #'(form ...)))
     (define state-forms (filter (lambda (form) (eq? (form-head-symbol form) 'state)) forms))
     (define action-forms (filter (lambda (form) (eq? (form-head-symbol form) 'action)) forms))
     (define transaction-forms (filter (lambda (form) (eq? (form-head-symbol form) 'commit-group)) forms))
     (define command-table-forms (filter (lambda (form) (eq? (form-head-symbol form) 'command-table)) forms))
     (define list-navigation-forms (filter (lambda (form) (eq? (form-head-symbol form) 'list-navigation)) forms))
     (define log-browser-forms (filter (lambda (form) (eq? (form-head-symbol form) 'log-browser)) forms))
     (define font-asset-forms (filter (lambda (form) (eq? (form-head-symbol form) 'font-asset)) forms))
     (define dynamic-font-cell-asset-forms (filter (lambda (form) (eq? (form-head-symbol form) 'dynamic-font-cell-asset)) forms))
     (define theme-forms (filter (lambda (form) (eq? (form-head-symbol form) 'theme)) forms))
     (define material-profile-forms (filter (lambda (form) (eq? (form-head-symbol form) 'material-profile)) forms))
     (define visual-preset-forms (filter (lambda (form) (eq? (form-head-symbol form) 'visual-preset)) forms))
     (define layout-forms
       (filter (lambda (form)
                 (not (memq (form-head-symbol form) '(state action commit-group command-table list-navigation log-browser font-asset dynamic-font-cell-asset theme material-profile visual-preset))))
               forms))
     (unless (= (length state-forms) 1)
       (raise-syntax-error 'noir-app "expects exactly one (state ...) form" stx))
     (unless (= (length layout-forms) 1)
       (raise-syntax-error 'noir-app "expects exactly one root layout form" stx))
     (unless (<= (length theme-forms) 1)
       (raise-syntax-error 'noir-app "accepts at most one (theme ...) declaration" stx))
     (unless (<= (length material-profile-forms) 1)
       (raise-syntax-error 'noir-app "accepts at most one (material-profile ...) declaration" stx))
     (when (and (pair? theme-forms) (pair? material-profile-forms))
       (raise-syntax-error 'noir-app "(theme ...) and (material-profile ...) are mutually exclusive compile-time token sources" stx))
     (unless (<= (length visual-preset-forms) 1)
       (raise-syntax-error 'noir-app "accepts at most one (visual-preset ...) declaration" stx))
     (define static-theme
       (cond
         [(pair? theme-forms) (parse-theme-form (car theme-forms))]
         [(pair? material-profile-forms) (parse-material-profile-form (car material-profile-forms))]
         [else #f]))
     (define static-visual-preset
       (if (pair? visual-preset-forms)
           (parse-visual-preset-form (car visual-preset-forms))
           (hash-ref visual-preset-table 'bench)))
     (define visual-language-datum
       `(visual-language-plan ',(hash-ref static-visual-preset 'id)
                              ,(hash-ref static-visual-preset 'width)
                              ,(hash-ref static-visual-preset 'height)
                              ,(hash-ref static-visual-preset 'margin)))
     (define states (parse-state-form (car state-forms)))
     (define state-indexes (state-index-by-id states))
     (define actions (parse-action-forms action-forms (list->set (map c-state-id states))))
     (define transactions (parse-transaction-forms transaction-forms (list->set (map c-state-id states))))
     (define command-specs (parse-command-table-forms command-table-forms (list->set (map c-action-id actions))))
     (define list-navigation-specs (parse-list-navigation-forms list-navigation-forms))
     (define log-browser-specs (parse-log-browser-forms log-browser-forms))
     (define font-asset-specs (parse-font-asset-forms font-asset-forms))
     (define font-assets (compile-font-asset-plans font-asset-specs))
     (define dynamic-font-cell-asset
       (and (pair? dynamic-font-cell-asset-forms)
            (compile-dynamic-font-cell-asset
             (parse-dynamic-font-cell-asset-forms dynamic-font-cell-asset-forms))))
     (define action-indexes (action-index-by-id actions))
     (define transaction-indexes (transaction-index-by-id transactions))
     (define-values (root-node _)
       (parameterize ([current-static-theme static-theme]
                      [current-static-font-assets font-assets]
                      [current-static-dynamic-font-cell-asset dynamic-font-cell-asset]
                      [current-static-visual-preset static-visual-preset])
         (parse-node (car layout-forms) (set))))
     (define-values (total dynamic budget updates)
       (with-static-font-assets font-assets (lambda () (compile-scene root-node))))
     (define layouts
       (parameterize ([current-static-visual-preset static-visual-preset])
         (with-static-font-assets font-assets (lambda () (compile-layout-plan root-node)))))
     (define rounded-surfaces
       (parameterize ([current-static-visual-preset static-visual-preset])
         (compile-rounded-surface-plan root-node layouts)))
     (define shadow-surfaces
       (parameterize ([current-static-visual-preset static-visual-preset])
         (compile-shadow-surface-plan root-node layouts)))
     (define-values (glyph-placements glyph-packets)
       (parameterize ([current-static-visual-preset static-visual-preset])
         (with-static-font-assets font-assets
           (lambda ()
             (with-static-dynamic-font-cell-asset dynamic-font-cell-asset
               (lambda () (compile-glyph-placement-plan root-node states layouts state-indexes)))))))
     (define subgroup-packets (compile-subgroup-packet-plan glyph-packets))
     (define packet-activity-contract (compile-packet-activity-contract subgroup-packets))
     (define base-packet-worklists (compile-packet-worklists subgroup-packets))
     (define events
       (parameterize ([current-static-visual-preset static-visual-preset])
         (compile-event-map root-node layouts action-indexes transaction-indexes)))
     (define tracks (compile-animation-tracks events))
     (define raw-plans
       (parameterize ([current-static-visual-preset static-visual-preset])
         (with-static-font-assets font-assets
           (lambda () (compile-action-plans root-node states actions layouts action-indexes)))))
     (define raw-schedule (compile-frame-schedule events tracks raw-plans))
     (define render-schedules
       (parameterize ([current-static-visual-preset static-visual-preset])
         (compile-render-schedules root-node layouts events tracks raw-plans glyph-placements glyph-packets raw-schedule)))
     (define-values (plans schedule)
       (compile-action-aware-tile-selection root-node layouts events raw-plans raw-schedule render-schedules))
     (define virtual-list-plans
       (parameterize ([current-static-visual-preset static-visual-preset])
         (compile-virtual-list-plans root-node layouts glyph-placements)))
     (define dynamic-font-cell-plan-datum
       (dynamic-font-cell-plan->datum dynamic-font-cell-asset virtual-list-plans glyph-placements))
     (define scrollbar-plans (compile-scrollbar-plans root-node layouts virtual-list-plans render-schedules))
     (define list-navigation-plans (compile-list-navigation-plans list-navigation-specs virtual-list-plans scrollbar-plans))
     (define log-browser-plans (compile-log-browser-plans log-browser-specs root-node layouts glyph-placements virtual-list-plans render-schedules))
     ;; Coalesced batch must be built after packet-local task annotation; this prevents a
     ;; runtime batch executor from reconstructing glyph dependencies.
     (define focus-graph
       (parameterize ([current-static-visual-preset static-visual-preset])
         (compile-focus-graph root-node layouts render-schedules state-indexes)))
     (define state-initial-by-id
       (for/hash ([state (in-list states)]) (values (c-state-id state) (c-state-initial state))))
     (define keyboard-map
       (with-static-font-assets font-assets
         (lambda () (compile-keyboard-map root-node focus-graph state-initial-by-id))))
     (define transaction-plans (compile-transaction-plans transactions focus-graph))
     (define keyboard-command-map (compile-keyboard-command-map root-node focus-graph plans action-indexes transaction-plans))
     (define command-matchers (compile-command-matchers command-specs root-node focus-graph plans action-indexes))
     (define packet-worklists (compile-task-packet-worklists base-packet-worklists subgroup-packets glyph-packets focus-graph transaction-plans))
     (define annotated-schedule (annotate-frame-task-worklists schedule packet-worklists focus-graph transaction-plans))
     (define conflicts (compile-conflict-graph annotated-schedule))
     (define raw-coalesced-batches (compile-frame-coalesced-batches annotated-schedule events conflicts root-node))
     ;; Composite slots are compiler-proved exact packet unions. They are lowered before
     ;; strategy selection so the selected executor consumes a complete immutable artifact.
     (define-values (composite-packet-worklists composite-coalesced-batches)
       (compile-composite-batch-worklists raw-coalesced-batches annotated-schedule packet-worklists focus-graph root-node))
     ;; profile selection 必须发生在 task tile IDs、winner writes、worklist slot 与 conflict proof 都已不可变之后。
     (define profile-selected-batches (compile-profile-guided-batch-strategies composite-coalesced-batches root-node))
     (define coalesced-batches (annotate-multi-action-fusion-admission profile-selected-batches events annotated-schedule root-node))
     (define row-activation-plans
       (compile-row-activation-plans root-node plans action-indexes annotated-schedule coalesced-batches))
     (with-syntax ([ROOT (datum-stx stx (node->datum root-node))]
                   [STATIC (datum-stx stx (- total dynamic))]
                   [DYNAMIC (datum-stx stx dynamic)]
                   [BUDGET (datum-stx stx `(quote ,budget))]
                   [STATE (datum-stx stx (state-table->datum states))]
                   [STATE-SLOTS (datum-stx stx (state-slots->datum states))]
                   [ACTION-SLOTS (datum-stx stx (action-slots->datum actions))]
                   [TRANSACTIONS (datum-stx stx (transaction-plans->datum transaction-plans))]
                   [COMMAND-MATCHERS (datum-stx stx (command-matchers->datum command-matchers))]
                   [ACTIONS (datum-stx stx `(list ,@(map (lambda (plan) (action-plan->datum plan state-indexes)) plans)))]
                   [UPDATES (datum-stx stx `(quote ,updates))]
                   [LAYOUT (datum-stx stx
                                        (parameterize ([current-static-visual-preset static-visual-preset])
                                          (layout-plan->datum layouts root-node states)))]
                   [GLYPH-PLACEMENTS (datum-stx stx (glyph-placement-plan->datum glyph-placements))]
                   [GLYPH-PACKETS (datum-stx stx (glyph-packets->datum glyph-packets))]
                   [SUBGROUP-PACKETS (datum-stx stx (subgroup-packets->datum subgroup-packets))]
                   [PACKET-ACTIVITY-CONTRACT (datum-stx stx (packet-activity-contract->datum packet-activity-contract))]
                   [PACKET-WORKLISTS (datum-stx stx (packet-worklists->datum composite-packet-worklists))]
                   [EVENTS (datum-stx stx (event-map->datum events))]
                   [TRACKS (datum-stx stx (animation-tracks->datum tracks))]
                   [SCHEDULE (datum-stx stx (frame-schedule->datum annotated-schedule))]
                   [CONFLICTS (datum-stx stx (conflict-graph->datum conflicts))]
                   [BATCHES (datum-stx stx (frame-coalesced-batches->datum coalesced-batches action-indexes annotated-schedule))]
                   [RENDER-SCHEDULES (datum-stx stx (render-schedules->datum render-schedules))]
                   [FOCUS-GRAPH (datum-stx stx (focus-graph->datum focus-graph))]
                   [KEYBOARD-MAP (datum-stx stx (keyboard-map->datum keyboard-map))]
                   [KEYBOARD-COMMAND-MAP (datum-stx stx (keyboard-command-map->datum keyboard-command-map))]
                   [VIRTUAL-LISTS (datum-stx stx (virtual-list-plans->datum virtual-list-plans))]
                   [ROW-ACTIVATIONS (datum-stx stx (row-activation-plans->datum row-activation-plans))]
                   [SCROLLBARS (datum-stx stx (scrollbar-plans->datum scrollbar-plans))]
                   [LIST-NAVIGATIONS (datum-stx stx (list-navigation-plans->datum list-navigation-plans))]
                    [LOG-BROWSERS (datum-stx stx (log-browser-plans->datum log-browser-plans))]
                    [FONT-ASSETS (datum-stx stx (font-asset-plans->datum font-assets))]
                     [DYNAMIC-FONT-CELL-PLAN (datum-stx stx dynamic-font-cell-plan-datum)]
                     [VISUAL-LANGUAGE (datum-stx stx visual-language-datum)]
                     [ROUNDED-SURFACES (datum-stx stx (rounded-surface-plan->datum rounded-surfaces))]
                     [SHADOW-SURFACES (datum-stx stx (shadow-surface-plan->datum shadow-surfaces))])
       #'(begin
           (define app-scene (scene ROOT STATIC DYNAMIC BUDGET STATE STATE-SLOTS ACTIONS ACTION-SLOTS TRANSACTIONS COMMAND-MATCHERS UPDATES LAYOUT GLYPH-PLACEMENTS GLYPH-PACKETS SUBGROUP-PACKETS PACKET-ACTIVITY-CONTRACT PACKET-WORKLISTS EVENTS TRACKS SCHEDULE CONFLICTS BATCHES RENDER-SCHEDULES FOCUS-GRAPH KEYBOARD-MAP KEYBOARD-COMMAND-MAP VIRTUAL-LISTS ROW-ACTIVATIONS SCROLLBARS LIST-NAVIGATIONS LOG-BROWSERS FONT-ASSETS DYNAMIC-FONT-CELL-PLAN VISUAL-LANGUAGE ROUNDED-SURFACES SHADOW-SURFACES))
           (provide app-scene)))]))
