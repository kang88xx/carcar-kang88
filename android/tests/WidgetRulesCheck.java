import com.kang88.carcar.WidgetRules;
public class WidgetRulesCheck {
  static int checks;
  static void check(boolean value) { checks++; if (!value) throw new AssertionError("check " + checks); }
  public static void main(String[] args) {
    var rules = WidgetRules.INSTANCE;
    check(rules.validTimestamp("2026-11-02T01:02:03.123456+00:00"));
    check(rules.validTimestamp("2026-11-02T01:02:03Z"));
    check(!rules.validTimestamp("2026-02-30T01:02:03Z"));
    check(!rules.validTimestamp("today"));
    check(!rules.validTimestamp("2026-11-02T01:02:03Zjunk"));
    check(rules.timestampMicros("2026-11-02T09:00:00+09:00") == rules.timestampMicros("2026-11-02T00:00:00Z"));
    check(rules.timestampMicros("2026-11-02T00:00:01Z") > rules.timestampMicros("2026-11-02T00:00:00Z"));
    check(rules.timestampMicros("bad") == Long.MIN_VALUE);
    // A late app fetch must not replace a widget record one microsecond newer.
    long earlier = rules.timestampMicros("2026-11-02T00:00:00.123455Z");
    long newer = rules.timestampMicros("2026-11-02T00:00:00.123456Z");
    check(newer > earlier);
    check(newer - earlier == 1);
    check(newer == rules.timestampMicros("2026-11-02T09:00:00.123456+09:00"));
    check(rules.timestampMicros("2026-11-02T00:00:00.1Z") == rules.timestampMicros("2026-11-02T00:00:00.100000Z"));
    check(rules.timestampMicros("2026-11-02T00:00:00.000001Z") - rules.timestampMicros("2026-11-02T00:00:00Z") == 1);
    check(rules.timestampMicros("1969-12-31T23:59:59.999999Z") == -1);
    String id = rules.requestId(""); java.util.UUID.fromString(id);
    check(rules.requestId(id).equals(id));
    check(!rules.requestId("").equals(id));
    check(rules.sameOperation("a", "a", "b", "b"));
    check(!rules.sameOperation("a", null, "b", "b")); // logout
    check(!rules.sameOperation("a", "other-car", "b", "b"));
    check(!rules.sameOperation("a", "a", "old-request", "b"));
    System.out.println("Widget rules: " + checks + " checks passed");
  }
}
