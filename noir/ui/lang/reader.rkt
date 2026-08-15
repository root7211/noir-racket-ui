#lang s-exp syntax/module-reader

;; 使用 collection module path，而不是相对文件路径：这样 `#lang noir/ui`
;; 无论从哪个项目目录加载，都稳定映射到 noir/ui/main。
noir/ui/main
