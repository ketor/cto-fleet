---
name: team-perf
description: 启动一个性能优化团队（profiler/analyzer×2/optimizer/benchmarker），通过基线采集+双路独立瓶颈分析+迭代优化+基准验证，对项目进行系统性性能优化。每次优化一个瓶颈，优化后立即验证，确保无回归。使用方式：/team-perf [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--focus=cpu,memory,io,latency,throughput] [--lang=zh|en] 性能问题描述或优化目标
argument-hint: [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--focus=cpu,memory,io,latency,throughput] [--lang=zh|en] 性能问题描述或优化目标
---

**参数解析**：从 `$ARGUMENTS` 中检测以下标志：
- `--auto`：完全自主模式（不询问用户任何问题，全程自动决策）
- `--once`：单轮确认模式（将所有需要确认的问题合并为一轮提问，确认后全程自动执行）
- `--focus=dim1,dim2`：聚焦性能维度（可选值：cpu/memory/io/latency/throughput，默认全面分析）
- `--lang=zh|en`：输出语言（默认 `zh` 中文）

解析后将标志从性能问题描述中移除。

| 模式 | 用户确认范围 | 条件节点处理 |
|------|-------------|-------------|
| **标准模式**（默认） | 每轮优化方案确认 + 基准对比确认 | 正常询问用户 |
| **单轮确认模式**（`--once`） | 仅首轮瓶颈分析确认 + 收尾汇总 | 自动决策 + 收尾汇总 |
| **完全自主模式**（`--auto`） | 不询问用户 | 全部自动决策，收尾汇总所有决策 |

单轮确认模式下自动决策规则：
- **瓶颈优先级不确定** → 按影响度排序，优先处理延迟和吞吐量影响最大的瓶颈
- **优化方案有多种选择** → 采纳对应分析维度 analyzer 的建议
- **迭代超 3 轮仍未达目标** → **不可跳过，必须暂停问用户**（熔断机制）
- **优化后性能反而下降** → **不可跳过，必须暂停问用户**（熔断机制）
- **双 analyzer 结论冲突** → optimizer 优先处理两者共识部分，冲突部分升级 team lead

完全自主模式下：所有节点均自动决策，不询问用户。熔断机制仍然生效（迭代超 3 轮、优化后性能下降时仍必须暂停问用户）。

使用 TeamCreate 创建 team（名称格式 `team-perf-{YYYYMMDD-HHmmss}`，如 `team-perf-20260308-143022`，避免多次调用冲突），你作为 team lead 按以下流程协调。

## 流程概览

```
阶段零  目标设定 → 解析性能目标，确定关注维度，明确量化指标
         ↓
阶段一  基线采集 → profiler 识别技术栈，运行 profiling/benchmark 工具，收集基线数据
         ↓
阶段二  双路瓶颈分析 → analyzer-1 算法/计算分析 + analyzer-2 资源/IO 分析（独立并行）
         → 合并分析 + 共识确认 → 瓶颈优先级排序 → 用户确认优化计划
         ↓
阶段三  迭代优化循环（每次一个瓶颈，最多 5 轮）：
         ├─ 优化：optimizer 实施优化（确保功能不变）
         ├─ 验证：benchmarker 运行基准测试，量化对比
         ├─ 判断：性能改善？回归？继续？
         └─ 下一个瓶颈
         ↓
阶段四  收尾 → 优化前后完整对比报告 + 清理
```

## 角色定义

| 角色 | 职责 |
|------|------|
| profiler | 识别项目技术栈和可用性能工具，运行性能分析工具（CPU profile、memory profile、benchmark、tracing），收集基线指标数据。输出基线性能报告。**仅在基线采集阶段工作，完成后关闭。** |
| analyzer-1 | **算法与计算效率分析**：从算法复杂度、计算密集度、热点函数、缓存效率角度分析 profiler 数据，定位计算相关瓶颈。输出结构化分析报告。**不编写或修改代码。独立分析，不与 analyzer-2 交流。** |
| analyzer-2 | **资源与 I/O 分析**：从 I/O 模式、内存分配/GC、并发竞争、资源利用率角度分析 profiler 数据，定位资源相关瓶颈。输出结构化分析报告。**不编写或修改代码。独立分析，不与 analyzer-1 交流。** |
| optimizer | 根据确认的瓶颈列表逐项实施优化。每次优化一个瓶颈，确保功能正确性不变。优化前简述方案，优化后运行已有测试确认无回归。**只做瓶颈相关优化，不做无关重构。** |
| benchmarker | 运行优化前后的基准测试，量化对比性能变化，检测性能回归，生成对比报告。**输出基准对比报告。** |

### 角色生命周期

| 角色 | 启动阶段 | 关闭时机 | 说明 |
|------|---------|---------|------|
| profiler | 阶段一（步骤 2） | 阶段一完成后（步骤 2 基线采集结束） | 基线数据交付后即释放 |
| analyzer-1 | 阶段一（步骤 2，与 profiler 并行） | 阶段三最后一轮优化验证后（步骤 12） | 需保留用于每轮优化后的阶段性评分更新 |
| analyzer-2 | 阶段一（步骤 2，与 profiler 并行） | 阶段三最后一轮优化验证后（步骤 12） | 需保留用于每轮优化后的阶段性评分更新 |
| optimizer | 阶段三（步骤 8） | 阶段四收尾前（步骤 13） | 全程保持存活直到收尾 |
| benchmarker | 阶段三（步骤 8） | 阶段四收尾前（步骤 13） | 全程保持存活直到收尾 |

---

## 评分体系

双 analyzer 按各自负责的维度独立评估，team lead 按权重合并为总体性能评分。满分 10 分。

### 性能维度分配

| 维度 | 权重 | 负责人 | 分析内容 |
|------|------|--------|---------|
| CPU/计算效率 | 25% | analyzer-1 | 热点函数、算法复杂度、计算密集循环、缓存命中率、向量化利用 |
| 内存使用 | 20% | analyzer-2 | 内存分配频率、GC 压力、内存泄漏、峰值内存、对象生命周期 |
| I/O 效率 | 20% | analyzer-2 | 磁盘 I/O 模式、网络调用、数据库查询、序列化开销、批处理 |
| 延迟/响应时间 | 20% | analyzer-1 | P50/P95/P99 延迟、关键路径耗时、同步阻塞、尾延迟 |
| 并发/吞吐量 | 15% | analyzer-2 | 锁竞争、并发模型、线程/协程利用率、队列积压、吞吐上限 |

**analyzer-1 总权重：45%**（CPU/计算效率 25% + 延迟/响应时间 20%）
**analyzer-2 总权重：55%**（内存使用 20% + I/O 效率 20% + 并发/吞吐量 15%）

**优化达标线：总分 ≥ 8.0 分 且无 Critical 瓶颈遗留**，双 analyzer 可宣布满意并提前结束迭代。

**`--focus` 参数处理**：如果用户指定了 `--focus`，对应维度的 analyzer 加大关注力度，optimizer 优先处理该维度瓶颈。未指定的维度仍输出评分但不作为优化重点。

### 共识合并机制

**共识度计算公式**：
```
对比每个瓶颈发现，统计两位 analyzer 的重叠情况：

共识瓶颈数 = 两者都识别出的瓶颈数量（指向相同函数/模块且描述相同类型问题）
总瓶颈数 = 去重后的瓶颈总数（合并两方发现后去重）

共识度 = 共识瓶颈数 / 总瓶颈数 × 100%
分歧度 = 100% - 共识度

分歧度 > 50%（超过一半瓶颈仅单方识别）→ team lead 将冲突部分升级，
optimizer 优先处理共识部分，冲突部分由 benchmarker 量化验证后决策。
```

独立分析后，team lead 将合并的完整报告（含双方分析和评分）发给两位 analyzer：
- 各自可调整**自己负责维度**的评分（看到对方的分析后校准）
- 不得修改对方维度的评分
- 两者共同识别的瓶颈标记为"共识瓶颈"，优先处理
- 仅单方识别的瓶颈标记为"待验证瓶颈"，需 benchmarker 量化确认
- **盲区检查**：team lead 检查是否存在两方都未覆盖的性能维度，如有则在报告中标注"未覆盖风险"

---

## 瓶颈严重程度分级

每个瓶颈按影响程度分级：

| 级别 | 含义 | 是否必须优化 |
|------|------|-------------|
| **Critical** | 性能劣化 >10x（指相对合理水平）、OOM 风险、系统级阻塞 | 必须优化 |
| **Major** | 性能劣化 2-10x、明显资源浪费、高延迟毛刺 | 强烈建议优化 |
| **Minor** | 性能劣化 <2x、可改进但不紧急 | 建议优化 |
| **Info** | 最佳实践建议、潜在优化空间 | 可选 |

---

## 阶段零：目标设定

### 步骤 1：解析性能目标

Team lead 解析用户提供的性能问题描述或优化目标：

1. 明确优化范围（整个项目 / 特定模块 / 特定接口）
2. 确定关注维度（根据 `--focus` 或从问题描述推断）
3. 识别量化目标（如有），未提供则默认"关键维度性能提升 ≥ 20%"

---

## 阶段一：基线采集

### 步骤 2：启动 profiler 和双 analyzer

三者并行启动。

**Profiler 基线采集**：
1. 阅读项目结构，识别技术栈、语言、框架和包管理器
2. 识别项目中已有的性能测试和基准测试（benchmark 文件、load test 配置）
3. **按技术栈选择并运行性能分析工具**。Profiler 必须先识别项目语言和框架，然后按以下决策树选择工具：

**工具选择决策树**（按项目语言/框架匹配）：

| 语言/框架 | CPU Profile | Memory Profile | Benchmark | 并发分析 | 检测方法 |
|-----------|-------------|---------------|-----------|---------|---------|
| **Go** | `go tool pprof -seconds=30 http://localhost:6060/debug/pprof/profile` 或 `go test -cpuprofile=cpu.prof` | `go tool pprof -alloc_space http://localhost:6060/debug/pprof/heap` | `go test -bench=. -benchmem -count=5 ./...` | `go tool pprof http://localhost:6060/debug/pprof/mutex` + `goroutine` | 检测 `go.mod` 文件 |
| **Python** | `py-spy record -o profile.svg -- python app.py` 或 `python -m cProfile -o output.prof app.py` | `memray run -o output.bin app.py && memray flamegraph output.bin` 或 `tracemalloc` | `pytest --benchmark-only` 或 `python -m timeit` | `py-spy dump --pid <PID>` 查看线程状态 | 检测 `pyproject.toml`/`requirements.txt`/`setup.py` |
| **Rust** | `cargo flamegraph` 或 `perf record --call-graph=dwarf ./target/release/app` | `valgrind --tool=dhat ./target/release/app` 或 `heaptrack` | `cargo bench`（criterion）或 `hyperfine './target/release/app'` | `perf lock record` | 检测 `Cargo.toml` |
| **Java/Kotlin** | `async-profiler -d 30 -f profile.html <PID>` 或 JFR: `jcmd <PID> JFR.start duration=30s filename=rec.jfr` | `async-profiler -e alloc -d 30 -f alloc.html <PID>` | JMH benchmark（检测 `@Benchmark` 注解） | `jstack <PID>` + `async-profiler -e lock` | 检测 `pom.xml`/`build.gradle` |
| **Node.js/TypeScript** | `clinic flame -- node app.js` 或 `node --prof app.js` | `node --heap-prof app.js` 或 `clinic heapprofiler` | `benchmark.js` 或 `hyperfine` | `clinic doctor -- node app.js` | 检测 `package.json` |
| **C/C++** | `perf record -g ./app && perf report` 或 `gprof ./app gmon.out` | `valgrind --tool=massif ./app && ms_print massif.out.*` | `google-benchmark` 或 `hyperfine './app'` | `perf lock record` + `valgrind --tool=helgrind` | 检测 `CMakeLists.txt`/`Makefile` |

**工具选择优先级**：① 项目已有的 benchmark/profile 配置 > ② 语言原生工具 > ③ 第三方工具 > ④ 通用工具（hyperfine/perf）

**Web 框架额外检测**：
- 如果是 HTTP 服务（检测路由定义/HTTP handler），额外运行负载测试：`wrk -t4 -c100 -d30s <URL>` 或 `k6 run` 或 `ab -n 10000 -c 100`
- 如果项目有 `docker-compose.yml` 或 `k8s` 配置，建议在容器内运行 profiling

收集基线数据的输出要求：

| 分析类别 | 必须输出的指标 |
|---------|-------------|
| CPU Profile | 热点函数 Top10（函数名 + CPU 时间占比 + 调用次数） |
| Memory Profile | 内存分配热点 Top10 + 峰值内存（MB） + GC 频率（次/分钟） |
| Benchmark | 各操作耗时（mean/median/P95） + ops/sec + 内存分配/op |
| Tracing | 关键路径耗时分解 + 系统调用 Top5 |
| I/O 分析 | I/O 等待时间占比 + 调用频率 + 数据吞吐量 |
| 并发分析 | 锁等待时间 Top5 + 线程/协程数量 + 竞争热点 |
| 负载测试 | QPS + P50/P95/P99 延迟 + 错误率 |

4. 如果项目有现有 benchmark，直接运行并记录结果作为基线
5. 如果没有现有 benchmark，profiler 编写关键路径的简单 benchmark
6. 输出**基线性能报告**发送给 team lead
7. Profiler 完成后关闭（不参与后续阶段）

**如果某工具未安装或无法运行**：profiler 标注"该指标不可用"，尝试替代工具，不阻塞流程。

**双 analyzer 同时阅读项目**：
- 阅读项目结构，理解技术栈、运行时特性和部署架构
- 了解已有性能相关配置（连接池、缓存配置、并发参数等）
- 各自输出项目概况给 team lead

### 步骤 3：分发基线数据

Team lead 收到 profiler 报告后，将基线数据分发给两位 analyzer，作为后续分析的基准。

Analyzer 在分析时必须以 profiler 的量化数据为依据——例如 profiler 显示某函数占 CPU 60%，analyzer-1 应重点分析该函数的算法效率。

---

## 阶段二：双路瓶颈分析

### 步骤 4：独立并行分析

两位 analyzer 各自分析负责的维度，**互不交流**。

**Analyzer-1（算法与计算效率）**：
- 分析 CPU profile，识别热点函数和调用路径
- 评估算法复杂度（O(n²) 等不必要高复杂度）、计算密集循环、缓存效率
- 评估关键路径延迟（P50/P95/P99 分布、同步阻塞点）
- 记录每个瓶颈：文件路径 + 函数 + 严重程度 + 瓶颈描述 + 影响量化 + 优化建议

**Analyzer-2（资源与 I/O）**：
- 分析 memory profile，识别内存分配热点和 GC 压力、泄漏风险
- 检查 I/O 模式（同步 I/O、批处理缺失、连接复用）、并发模型（锁竞争、线程利用率）
- 评估资源利用率（连接池、缓存命中率、队列深度）
- 记录每个瓶颈：文件路径 + 函数 + 严重程度 + 瓶颈描述 + 影响量化 + 优化建议

### 步骤 5：合并分析 + 共识确认

两份分析报告完成后：

1. **Team lead 合并报告**：将两份报告合并为一份完整瓶颈分析报告（5 个维度全覆盖）
2. **共识确认**：将合并报告发给两位 analyzer，各自查看对方的分析，可调整自己维度的评分
3. **标记共识**：两者共同指出的瓶颈标记为"共识瓶颈"
4. **Team lead 计算总分**：按权重加权

分析报告格式：

```
## 性能分析报告

### 总体性能评分：X.X / 10.0

### 基线指标（来自 profiler）
- CPU 热点 Top5：[函数列表 + 占比]
- 峰值内存：XXX MB | GC 频率：XX 次/分钟
- 关键接口 P95 延迟：XX ms | QPS：XXXX
- I/O 等待占比：XX% | 锁竞争率：XX%

### 各维度评分
**算法与计算维度（analyzer-1）**：
- CPU/计算效率：X.X/10 - [理由]
- 延迟/响应时间：X.X/10 - [理由]

**资源与 I/O 维度（analyzer-2）**：
- 内存使用：X.X/10 - [理由]
- I/O 效率：X.X/10 - [理由]
- 并发/吞吐量：X.X/10 - [理由]

### 瓶颈列表（按影响度排序）
1. [Critical] ★共识 文件:函数 - 瓶颈描述 - 影响量化 - 优化建议 - 来源：analyzer-1/analyzer-2/共识
2. [Major] 文件:函数 - 瓶颈描述 - 影响量化 - 优化建议 - 来源：analyzer-1/analyzer-2
...
```

### 步骤 6：优化优先级排序

Team lead 对合并后的瓶颈列表做优先级排序：

```
瓶颈 1：[瓶颈描述] — 优先级：P0 — 预期收益：[量化预估]
  维度：CPU/计算效率
  影响：占 CPU 60%，P95 延迟主因
  优化方向：[策略描述]

瓶颈 2：[瓶颈描述] — 优先级：P1 — 预期收益：[量化预估]
  维度：内存使用
  影响：GC 压力导致延迟毛刺
  优化方向：[策略描述]
```

**优先级规则**：
- 共识瓶颈优先于单方瓶颈
- Critical > Major > Minor > Info
- `--focus` 指定的维度相关瓶颈优先
- 预期收益大的优先

### 步骤 7：用户确认优化计划

Team lead 向用户展示：
- 性能分析报告摘要（总分 + 基线指标 + 各维度评分）
- 瓶颈优先级列表（每个瓶颈的描述 + 影响 + 预期收益）
- 建议的优化顺序

AskUserQuestion 确认：接受计划 / 调整优化顺序 / 排除某些瓶颈 / 补充约束（如"不改 schema"）

**单轮确认模式**：首轮分析报告必须经用户确认。
**完全自主模式**：自动决策，不询问用户。

**如果初始评分已 ≥ 8.0 且无 Critical 瓶颈**：
- 向用户展示报告，询问是否仍需优化（可能有 Minor 级别的优化空间）
- 用户选择结束则直接跳到阶段四收尾

---

## 阶段三：优化实施

**每次优化一个瓶颈，优化后立即验证。** 最多 5 轮。

### 步骤 8：启动 optimizer 和 benchmarker

首次进入阶段四时启动 optimizer 和 benchmarker，两者全程保持存活直到收尾。

### 步骤 9：Optimizer 实施优化

Optimizer 按瓶颈优先级逐项优化：

1. **优化前方案简述**：对当前瓶颈，optimizer 先用 1-3 句描述优化方案发送给 team lead
   - Team lead 将方案转发给对应维度的 analyzer 快速确认方向
   - Analyzer 确认后 optimizer 开始编码
   - **单轮确认模式/完全自主模式**：跳过方案确认，optimizer 直接实施
2. **编码优化**：
   - 严格针对当前瓶颈优化，不做无关改动
   - 确保功能正确性不变（保持接口契约、返回值语义一致）
   - 常见手段：算法降复杂度、缓存引入、I/O 批处理/异步化、对象池/减分配、锁粒度优化/并行化
   - 无法优化的瓶颈标注原因，通知 team lead
3. **自检**（提交前必须完成）：
   - 运行全量测试套件确保无功能回归
   - 运行 lint/format（如项目有配置）
   - 自检通过后才通知 benchmarker

### 步骤 10：Benchmarker 验证

Optimizer 自检通过后，benchmarker 执行验证：

**性能基准对比**：
- 运行与基线相同的 benchmark 套件，对比关键指标（耗时、内存、QPS 等）
- 计算性能变化百分比，检测是否有性能回归（其他指标变差）

**功能回归检查**：
- 运行全量测试套件（含集成测试/端到端测试），确认全部通过

Benchmarker 输出**基准对比报告**：

```
## 基准对比报告 - 瓶颈 X 优化后

### 目标瓶颈：[瓶颈描述]

### 性能变化
| 指标 | 优化前 | 优化后 | 变化 | 判定 |
|------|--------|--------|------|------|
| [指标名] | XXX | XXX | ↓XX% | ✅ 改善 |
| [指标名] | XXX | XXX | →0% | ➡️ 无变化 |
| [指标名] | XXX | XXX | ↑XX% | ❌ 回归 |

### 功能测试：全部通过 / X 个失败
### 判定：✅ 优化有效 / ❌ 需要回退 / ⚠️ 部分改善
```

**如果性能回归**：
- Benchmarker 报告回归详情
- Optimizer 分析原因并调整方案
- 当次瓶颈最多重试 2 次，仍无改善则跳过该瓶颈并标注
- **单轮确认模式/完全自主模式下性能回归必须暂停问用户**（熔断机制）

**如果功能测试失败**：
- Optimizer 修复功能回归（不计入轮次），重新自检 + benchmarker 重新验证
- 当次修复最多重试 2 次，仍失败则回退该优化并升级 team lead

### 步骤 11：阶段性评估

每个瓶颈优化完成后，team lead 更新性能评分：

1. 将 benchmarker 对比数据发给对应维度的 analyzer
2. Analyzer 根据实际改善效果更新该维度评分
3. Team lead 重新计算总分

输出阶段性报告（格式同步骤 5，轮次递增），**与上一轮对比**：标注每个维度的分数变化（↑/↓/→）和关键指标变化。

### 步骤 12：判断是否继续

Team lead 根据验证结果决定：

**达标（总分 ≥ 8.0 且无 Critical 瓶颈遗留）**：
- 双 analyzer 宣布满意
- 跳到阶段四收尾

**达到量化目标（如用户指定）**：
- 目标指标已达成
- 跳到阶段四收尾

**未达标但有改善**：
- **标准模式**：向用户展示本轮对比数据和分数变化，AskUserQuestion 确认是否继续优化下一个瓶颈
- **单轮确认模式**：自动继续下一个瓶颈（第 3 轮后触发熔断，必须问用户）
   - **完全自主模式**：自动继续下一个瓶颈（第 3 轮后触发熔断，必须问用户）

**未达标且优化无效（性能变化 < 5%）**：
- 暂停，向用户报告情况，建议调整策略或终止

**达到第 5 轮仍未达标**：
- 强制停止，输出完整优化历程 + 剩余瓶颈

---

## 阶段四：收尾

### 步骤 13：最终对比报告

Team lead 按 `--lang` 指定的语言向用户输出：

```
## 性能优化最终报告

### 元信息
- 生成时间：YYYY-MM-DD HH:mm:ss
- 团队名称：team-perf-{YYYYMMDD-HHmmss}
- 执行模式：标准模式 / 单轮确认模式 / 完全自主模式
- 输出语言：zh / en
- 聚焦维度：[--focus 参数值 或 "全面分析"]
- 优化目标：[用户描述的性能目标]

### 评分历程
| 轮次 | 总分 | CPU/计算 | 内存 | I/O | 延迟 | 并发/吞吐 |
|------|------|---------|------|-----|------|----------|
| 基线 | X.X  | ...     | ...  | ... | ...  | ...      |
| 瓶颈1 | X.X | ...     | ...  | ... | ...  | ...      |
| ...  | ...  | ...     | ...  | ... | ...  | ...      |

### 关键指标对比
| 指标 | 优化前 | 优化后 | 改善幅度 |
|------|--------|--------|---------|
| 热点函数 CPU 占比 | XX% | XX% | ↓XX% |
| 峰值内存 | XXX MB | XXX MB | ↓XX% |
| P95 延迟 | XX ms | XX ms | ↓XX% |
| QPS | XXXX | XXXX | ↑XX% |
| GC 频率 | XX 次/分钟 | XX 次/分钟 | ↓XX% |
| I/O 等待占比 | XX% | XX% | ↓XX% |

### 优化统计
- 瓶颈处理：X 个瓶颈（优化 Y 个 / 跳过 Z 个）
- Critical 处理：X/Y 个
- Major 处理：X/Y 个
- 总体性能提升：XX%（加权平均）

### 已实施优化
1. [瓶颈描述] - 优化策略 - 效果：[量化改善]
2. ...

### 遗留瓶颈（如有）
1. [描述] - 未优化原因
2. ...

### 自主决策汇总（单轮确认模式/完全自主模式）
| 决策节点 | 决策内容 | 理由 |
|---------|---------|------|
| [阶段/步骤] | [决策描述] | [理由] |

### 附录：分析共识说明
- analyzer-1 识别的瓶颈：[数量] 个
- analyzer-2 识别的瓶颈：[数量] 个
- 共识瓶颈：[数量] 个（共识度 = XX%）
- 仅 analyzer-1 识别：[列表]
- 仅 analyzer-2 识别：[列表]
- 分歧处理记录：[如有评分校准，记录校准前后差值和理由]
- 盲区标注：[未覆盖的性能维度，如有]
```

### 步骤 13.5：跨团队衔接建议（可选）

Team lead 根据项目情况向用户建议后续动作：
- **发现安全相关性能问题（如加密开销过大）**：建议运行 `/team-security` 评估安全与性能的平衡方案
- **优化涉及架构层面变更**：建议运行 `/team-arch` 评估架构改进方案
- **优化后代码需要质量保证**：建议运行 `/team-review` 对优化代码做全面审查
- 用户可选择执行或跳过，不强制。

### 步骤 14：清理

关闭所有 teammate，用 TeamDelete 清理 team。

---

## 核心原则

- **数据驱动**：所有分析基于 profiler 量化数据，不做主观臆断
- **双路互补**：算法/计算分析 + 资源/IO 分析独立并行，共识优先处理
- **逐项优化**：每次只优化一个瓶颈，优化后立即验证，确保可回溯
- **量化对比**：每次优化都有 before/after 基准数据，用数字说明效果
- **功能不变**：所有优化必须保证功能正确性不变，测试全量通过
- **有限迭代**：最多 5 轮，第 3 轮后单轮确认模式/完全自主模式触发熔断
- **不引入回归**：optimizer 自检 + benchmarker 全量验证，双重保障

---

## 常用性能工具参考

| 语言/平台 | CPU Profile | Memory Profile | Benchmark |
|-----------|-------------|---------------|-----------|
| Go | go tool pprof (cpu) | go tool pprof (heap/allocs) | go test -bench |
| Python | py-spy, cProfile | memray, tracemalloc | pytest-benchmark |
| Rust | cargo flamegraph, perf | DHAT, heaptrack | criterion |
| Java/Kotlin | async-profiler, JFR | async-profiler (alloc) | JMH |
| Node.js | clinic, 0x | --heap-prof | benchmark.js |
| C/C++ | perf, gprof | valgrind massif | google benchmark |
| 通用 | perf, flamegraph | valgrind | hyperfine |

---

## 错误处理

| 异常情况 | 处理方式 |
|---------|---------|
| 项目无法构建/运行 | Optimizer 优先修复构建问题，再进行性能优化 |
| 没有现有 benchmark | Profiler 为关键路径编写简单 benchmark，作为基线 |
| 性能工具未安装/无法运行 | Profiler 标注"该指标不可用"，尝试替代工具，不阻塞流程 |
| 优化导致功能回归 | Optimizer 回退优化，分析原因后重新设计方案 |
| 优化后性能反而下降 | 单轮确认模式/完全自主模式下触发熔断问用户；标准模式直接询问用户是否回退 |
| 双 analyzer 结论冲突 | Optimizer 优先处理共识部分；冲突部分由 benchmarker 量化验证后决策 |
| Benchmark 结果不稳定（方差过大） | Benchmarker 增加运行次数、排除异常值、报告置信区间 |
| 优化涉及架构变更 | 暂停，升级用户确认是否在本次范围内 |
| Teammate 无响应/崩溃 | Team lead 重新启动同名 teammate（传入完整上下文），从当前轮次恢复。如果是 optimizer 崩溃，检查已有代码变更决定是否保留。 |
| 外部依赖瓶颈（数据库、第三方 API） | Analyzer 标注为外部瓶颈，建议应用层缓解策略（缓存、重试、限流） |
| 项目过大无法完整分析 | Profiler 聚焦用户指定的模块或性能热点区域；analyzer 仅分析 profiler 数据覆盖的范围 |
| 无测试框架/测试基础设施 | Optimizer 跳过全量测试自检，改为手动验证优化后功能正确性；在总结中标注"无自动化测试保障"风险 |

---

## 需求

$ARGUMENTS
