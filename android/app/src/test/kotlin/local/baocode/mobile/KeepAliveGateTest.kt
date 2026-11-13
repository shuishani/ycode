package local.baocode.mobile

import local.baocode.mobile.KeepAliveGate.Phase
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class KeepAliveGateTest {
    @Test
    fun serviceConfirmationIsTheOnlyWayToRun() {
        val gate = KeepAliveGate()
        val token = gate.begin()!!
        assertEquals(Phase.PENDING, gate.phase)
        assertTrue(gate.confirm(token))
        assertEquals(Phase.RUNNING, gate.phase)
    }

    @Test
    fun duplicateStartIsRejectedWhilePendingOrRunning() {
        val gate = KeepAliveGate()
        val token = gate.begin()!!
        assertNull(gate.begin())
        gate.confirm(token)
        assertNull(gate.begin())
    }

    @Test
    fun failedStartNeverRunsAndLateServiceIsRejected() {
        val gate = KeepAliveGate()
        val token = gate.begin()!!
        assertEquals(Phase.PENDING, gate.end(token))
        assertEquals(Phase.IDLE, gate.phase)
        assertFalse(gate.confirm(token))
        assertEquals(Phase.IDLE, gate.phase)
    }

    @Test
    fun stopIsIdempotent() {
        val gate = KeepAliveGate()
        val token = gate.begin()!!
        gate.confirm(token)
        assertEquals(Phase.RUNNING, gate.end())
        assertNull(gate.end())
        assertNull(gate.end(token))
        assertEquals(Phase.IDLE, gate.phase)
    }

    @Test
    fun stoppingWhilePendingRejectsTheLateService() {
        val gate = KeepAliveGate()
        val old = gate.begin()!!
        assertEquals(Phase.PENDING, gate.end())
        assertFalse(gate.confirm(old))
        assertEquals(Phase.IDLE, gate.phase)
    }

    @Test
    fun staleServiceCallbacksDoNotAffectANewerStart() {
        val gate = KeepAliveGate()
        val old = gate.begin()!!
        gate.end()
        val next = gate.begin()!!
        assertNotEquals(old, next)
        assertFalse(gate.confirm(old))
        assertNull(gate.end(old))
        assertEquals(Phase.PENDING, gate.phase)
        assertTrue(gate.confirm(next))
        assertNotNull(gate.end(next))
    }
}
