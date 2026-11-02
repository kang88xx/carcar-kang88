import com.kang88.carcar.PushRegistrationGate;

public final class PushRegistrationGateCheck {
    private static int checks = 0;
    private static void check(boolean value, String name) {
        if (!value) throw new AssertionError(name);
        checks++;
    }
    public static void main(String[] args) {
        PushRegistrationGate gate = new PushRegistrationGate();
        Long first = gate.begin();
        check(first != null, "initial registration starts");
        check(gate.begin() == null, "concurrent permission request rejected");
        check(!gate.beginDiscardIfIdle(), "token callback cannot delete active registration");
        gate.cancel();
        check(!gate.isCurrent(first), "logout invalidates pending token");
        Long second = gate.begin();
        check(second != null && !second.equals(first), "new explicit opt-in uses new generation");
        check(!gate.finish(first), "old token cannot complete new account registration");
        check(gate.isCurrent(second), "new request survives stale callback");
        check(gate.finish(second), "only current completion succeeds");
        check(!gate.finish(second), "completion cannot run twice");
        gate.beginDelete();
        gate.beginDelete();
        check(gate.begin() == null, "deleting tokens blocks re-registration");
        gate.endDelete();
        check(gate.begin() == null, "all overlapping deletions must finish");
        gate.endDelete();
        check(gate.beginDiscardIfIdle(), "late token can be deleted only while idle");
        check(gate.begin() == null, "late deletion also blocks new registration");
        gate.endDelete();
        check(gate.begin() != null, "registration resumes after cleanup");
        System.out.println("PASS: " + checks + " push registration lifecycle checks");
    }
}
