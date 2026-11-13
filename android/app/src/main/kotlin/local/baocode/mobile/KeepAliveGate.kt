package local.baocode.mobile

/**
 * 后台保连接的纯状态机（无 Android 依赖，可在 JVM 单测）。
 * 每次启动请求有一个递增令牌；Service 只有带着当前待确认的令牌才能把状态推进到 RUNNING，
 * 迟到的、已取消的或过期的启动都会被拒绝，不会空跑。
 */
internal class KeepAliveGate {
    enum class Phase { IDLE, PENDING, RUNNING }

    var phase = Phase.IDLE
        private set
    var token = 0L
        private set
    private var issued = 0L

    /** IDLE 时开始一次启动并返回新令牌；已在启动中或运行中返回 null（去重）。 */
    fun begin(): Long? {
        if (phase != Phase.IDLE) return null
        issued += 1
        token = issued
        phase = Phase.PENDING
        return token
    }

    /** Service 已真正进入前台。只有当前待确认的令牌有效，其余一律拒绝。 */
    fun confirm(candidate: Long): Boolean {
        if (phase != Phase.PENDING || candidate != token) return false
        phase = Phase.RUNNING
        return true
    }

    /**
     * 失败、停止或结束，幂等。[candidate] 非 null 时必须与当前令牌一致，
     * 否则视为旧 Service 的迟到回调并忽略（返回 null）。返回结束前的阶段，已空闲则返回 null。
     */
    fun end(candidate: Long? = null): Phase? {
        if (phase == Phase.IDLE) return null
        if (candidate != null && candidate != token) return null
        val previous = phase
        phase = Phase.IDLE
        return previous
    }
}
