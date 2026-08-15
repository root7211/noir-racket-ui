# Fixed Command Matcher / Command Dispatch Table

**作者：Manus AI**

## 目标

本阶段将 Command Palette 从“提交一个 fixed-capacity ASCII token”扩展为**编译期固定的命令匹配器**。命令 literal 在 Racket macro expansion 期被编码为 `(focus_slot, length, packed-u64)`，并绑定唯一的 Action Slot。Enter 事件期不执行字符串比较、分词、哈希查询或动态命令注册。

```racket
(command-table #:field command-entry
  (command "GPU" #:action gpu-command))
```

## 编译期 ABI

`command-table` 只接受 1–8 个 `A–Z` 或空格的 literal，且 action 必须是同一 `noir-app` 中已声明的 action。Compiler 对每项产生 `command-matcher`：

| 字段 | `GPU` 的固定值 | 作用 |
|---|---:|---|
| `focus_slot` | 0 | 仅匹配 command-entry 的 active slot |
| `length` | 3 | 由 cursor 直接比较 |
| `packed` | `5591111` / `0x00555047` | little-endian packed ASCII key |
| `action_index` | 0 | canonical Action Slot 地址 |
| `tile_ids` | `[0, 1]` | field tile 与 action tile 的编译期并集 |

Racket 宏阶段证明：field 为 `ascii-upper`、literal 可由 8-byte register 表示、Action Slot 存在、每个 `(field,length,packed)` 唯一、并且 matcher tile set 等于 field/action tile union。Scene JSON 明确导出 `command_matchers`，便于宿主 admission 和外部审计。

## Rust 宿主执行

Rust 启动期解码每个 matcher，并验证：focus slot 与 field ID 对应、field 有 page-1 ASCII descriptor、literal 的 bytes 重新 pack 后等于 compiler `packed`、Action Slot name/index 对应，以及 tile union 正确。通过 admission 后，宿主只保存 `CompiledCommandMatcher { focus_slot, length, packed, action_index, tile_mask }`。

Enter 的固定路径为：

```text
focus slot + cursor + packed pending u64
  → compiler matcher table
  → Action Slot index
  → fixed state-slot writes + fixed GPU write ranges + tile mask
```

如果某 field 有 compiler matcher entries，任何未命中 `(cursor, packed)` 都输出固定 reject，并保证 `state_writes=0`、`gpu_writes=0`。因此不再回退到普通 `commit-pending-register`，避免未知 token 进入业务状态。

## Command Palette 真实验证

`examples/command-palette.rkt` 声明 `GPU → gpu-command`。`tools/verify_command_matcher.sh` 在 Xvfb、真实 winit window 与 wgpu renderer 上执行两条路径。

| 输入 | 预期 | 真实 oracle |
|---|---|---|
| `G → P → U → Enter` | 命中 `action_index=0` | `command-applied` State Slot 0 通过固定 action plan 增加 1 |
| `Escape` | field-local 清理 | 仅 command-entry 的 page-1 glyph cells/cursor/packed pending reset |
| `X → Enter` | 未知命令拒绝 | 日志确认 `state_writes=0 gpu_writes=0` |

验证矩阵已通过：Racket 全量 regression 为 **0 个 FAILURE**；Rust release host 构建通过；真实 Command Matcher X11/wgpu oracle 通过。

## 可复现命令

```bash
cd /home/ubuntu/noir_review/noir-racket-ui
PLTCOLLECTS="$PWD:" racket tests/run.rkt
cd wgpu-verify && cargo build --release --bin noir_winit_host
cd .. && tools/verify_command_matcher.sh
```

## 当前边界

本阶段 matcher target 是 Action Slot。已有 transaction 机制已可由 form/transaction button 触发；若要把命令 literal 直接绑定到 Reset All 或 Apply All transaction，可在 matcher entry 中增加 mutually-exclusive `transaction_index` / operation tag，沿用现有 fixed transaction executor。匹配层本身无需改为通用 parser。
