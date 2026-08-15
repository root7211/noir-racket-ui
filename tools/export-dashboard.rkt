#lang racket/base

(require racket/cmdline
         racket/file
         racket/format
         racket/list
         racket/runtime-path
         racket/string
         "../noir/ui/main.rkt")

;; 构建 identity 是可复现的输入摘要，而不是输出 Scene JSON 的自指 hash。
;; DSL、编译器 ABI、profile 内容或 target 改变，都会产生不同 source fingerprint；
;; Rust calibration manifest 随后可据此绑定证据。
;; admission policy 不参与 source identity：它是同一 build input 的准入行为，允许 permissive bootstrap
;; artifact 被严格策略复用；policy 本身仍作为 attestation 的信息字段记录。
(define-runtime-path tool-directory ".")
(define-runtime-path builder-source-path "export-dashboard.rkt")
(define project-root (simplify-path (build-path tool-directory 'up)))
(define build-attestation-schema "noir-build-attestation-v1")
(define compiler-abi "noir-racket-ui-abi-v2")
(define scene-json-abi "noir-scene-json-v2")
(define target-width 640)
(define target-height 360)
(define quad-instance-bytes 48)
(define glyph-cell-bytes 32)

(define (absolute path)
  (simplify-path (path->complete-path path project-root)))

(define (file-fingerprint path)
  (cond [(and path (file-exists? path))
         (string-append "fnv1a64:" (fnv1a64-hex (file->bytes path)))]
        [else "absent"]))

(define (fnv1a64 bytes)
  (define offset #xcbf29ce484222325)
  (define prime #x100000001b3)
  (define mask #xffffffffffffffff)
  (for/fold ([hash offset]) ([byte (in-bytes bytes)])
    (bitwise-and mask (* (bitwise-xor hash byte) prime))))

(define (fnv1a64-hex bytes)
  (define raw (number->string (fnv1a64 bytes) 16))
  (string-append (make-string (max 0 (- 16 (string-length raw))) #\0) raw))

(define (environment-string key [fallback "none"])
  (define value (getenv key))
  (if (and value (not (string=? value ""))) value fallback))

(define entry-module (environment-string "NOIR_ENTRY_MODULE" "examples/dashboard.rkt"))
(define dashboard-path (absolute entry-module))
(define compiler-path (absolute "noir/ui/main.rkt"))
(define profile-path (getenv "NOIR_COST_PROFILE"))
(define profile-id (environment-string "NOIR_PROFILE_ID"))
(define admission-policy (environment-string "NOIR_PROFILE_ADMISSION" "permissive"))

;; Ordered list 是 FNV 的唯一输入，避免 JSON hash key order 进入 identity。
(define canonical-build-input
  (list (list 'schema build-attestation-schema)
        (list 'compiler_abi compiler-abi)
        (list 'scene_json_abi scene-json-abi)
        (list 'target (list target-width target-height quad-instance-bytes glyph-cell-bytes))
        (list 'entry_module entry-module)
        (list 'entry_source (file-fingerprint dashboard-path))
        (list 'compiler_source (file-fingerprint compiler-path))
        (list 'builder_source (file-fingerprint builder-source-path))
        (list 'profile_id profile-id)
        (list 'profile_registry (file-fingerprint profile-path))))

(define source-fingerprint
  (string-append "fnv1a64:"
                 (fnv1a64-hex (string->bytes/utf-8 (format "~s" canonical-build-input)))))

(define build-attestation
  (hash 'schema build-attestation-schema
        'source_fingerprint_fnv1a64 source-fingerprint
        'compiler_abi compiler-abi
        'scene_json_abi scene-json-abi
        'target (hash 'width target-width
                      'height target-height
                      'quad_instance_bytes quad-instance-bytes
                      'glyph_cell_bytes glyph-cell-bytes)
        'profile_id profile-id
        'profile_admission admission-policy
        'canonical_input (hash 'entry_module entry-module
                               'entry_source (file-fingerprint dashboard-path)
                               'compiler_source (file-fingerprint compiler-path)
                               'builder_source (file-fingerprint builder-source-path)
                               'profile_registry (file-fingerprint profile-path))))

(define out-path
  (command-line
   #:program "export-dashboard.rkt"
   #:args (path)
   path))

;; `dashboard.rkt` 的 `#lang noir/ui` 必须在 automatic fingerprint 已存在的环境中展开。
;; 不使用 putenv，避免污染外层 test process 或把 identity 变成全局可变状态。
(define builder-environment (environment-variables-copy (current-environment-variables)))
(environment-variables-set! builder-environment
                            #"NOIR_CANONICAL_SOURCE_FINGERPRINT"
                            (string->bytes/utf-8 source-fingerprint))

(define app-scene
  (parameterize ([current-environment-variables builder-environment])
    (dynamic-require dashboard-path 'app-scene)))

(call-with-output-file out-path
  (lambda (out) (write-scene-json app-scene out #:build-attestation build-attestation))
  #:exists 'truncate/replace)

(fprintf (current-error-port)
         "noir build attestation: source_fingerprint=~a compiler_abi=~a profile=~a policy=~a\n"
         source-fingerprint compiler-abi profile-id admission-policy)
