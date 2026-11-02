import com.kang88.carcar.LauncherIconAliases;
import java.util.*;
import kotlin.Pair;

public final class LauncherIconAliasesCheck {
    private static final LauncherIconAliases rules = LauncherIconAliases.INSTANCE;
    private static int assertions;
    private static void check(boolean value, String message) {
        assertions++;
        if (!value) throw new AssertionError(message);
    }
    private static Map<String, Integer> initial() {
        Map<String, Integer> states = new LinkedHashMap<>();
        for (String alias : rules.getAliases().values()) states.put(alias, 0);
        return states;
    }
    private static void apply(Map<String, Integer> states, String id) {
        for (Pair<String, Integer> change : rules.changes(id)) states.put(change.getFirst(), change.getSecond());
    }
    private static void rejects(Runnable work, String message) {
        boolean rejected = false;
        try { work.run(); } catch (IllegalArgumentException | IllegalStateException expected) { rejected = true; }
        check(rejected, message);
    }
    public static void main(String[] args) {
        check(rules.getAliases().size() == 12, "default + 11 floor aliases");
        check(rules.current(initial()) == null, "fresh install uses default icon");
        int transitions = 0;
        for (String from : rules.getAliases().keySet()) {
            for (String to : rules.getAliases().keySet()) {
                Map<String, Integer> states = initial();
                apply(states, from);
                for (Pair<String, Integer> change : rules.changes(to)) {
                    states.put(change.getFirst(), change.getSecond());
                    long enabled = states.entrySet().stream().filter(e -> rules.enabled(e.getKey(), e.getValue())).count();
                    check(enabled >= 1, "an interrupted transition must leave a launchable entry");
                }
                check(Objects.equals(rules.current(states), to), "all transitions restore exactly requested icon");
                transitions++;
            }
        }
        for (String invalid : new String[]{"", "floor_f0", "floor_f6", "floor_b0", "floor_b7", "F1", "car_blue", "../../MainActivity"}) {
            rejects(() -> rules.changes(invalid), "reject invalid icon before changing components");
        }
        Map<String, Integer> none = initial();
        none.replaceAll((k, v) -> 2);
        rejects(() -> rules.current(none), "no launcher entry cannot be reported as default");
        Map<String, Integer> duplicate = initial();
        duplicate.put(rules.aliasFor("floor_b2"), 1);
        rejects(() -> rules.current(duplicate), "multiple entries cannot be reported as success");
        Map<String, Integer> missing = initial();
        missing.remove(rules.aliasFor("floor_f1"));
        rejects(() -> rules.current(missing), "missing manifest alias is invalid");
        System.out.println("PASS: " + transitions + " floor/default transitions, interruption safety, invalid IDs and ambiguous state; " + assertions + " assertions");
    }
}
