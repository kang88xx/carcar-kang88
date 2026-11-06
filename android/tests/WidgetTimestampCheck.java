import com.kang88.carcar.WidgetTimestamp;
import java.time.Instant;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;

public class WidgetTimestampCheck {
    private static int checks;
    private static final Date NOW = Date.from(Instant.parse("2026-11-06T10:00:00Z"));

    private static void equal(String actual, String expected) {
        if (!actual.equals(expected)) throw new AssertionError(actual + " != " + expected);
        checks++;
    }

    private static String format(String value) {
        return WidgetTimestamp.INSTANCE.format(value, NOW);
    }

    public static void main(String[] args) {
        // Korean-first UI remains Korean even when the device language is English.
        Locale.setDefault(Locale.US);
        TimeZone.setDefault(TimeZone.getTimeZone("Asia/Seoul"));
        String expected = "11월 6일 18:42 기록";
        equal(format("2026-11-06T09:42:00.123456Z"), expected);
        equal(format("2026-11-06T09:42:00Z"), expected);
        equal(format("2026-11-06T09:42:00.123456+00:00"), expected);
        equal(format("2026-11-06T18:42:00+09:00"), expected);
        equal(format("2026-11-06T09:42:00.1Z"), expected);
        equal(format("2026-11-06T09:42:00.123Z"), expected);
        equal(format("2025-11-06T09:42:00Z"), "2025년 11월 6일 18:42 기록");
        equal(format("2027-11-06T09:42:00Z"), "2027년 11월 6일 18:42 기록");
        equal(format("2025-12-31T15:01:00Z"), "1월 1일 00:01 기록");
        for (String invalid : new String[] {
                "2026-02-30T00:00:00Z", "2026-11-06T09:42:00Zgarbage",
                "2026-11-06T09:42:00", "2026-11-06T09:42:00+99:00",
                "2026-11-06T09:42:00.1234567Z", null, ""}) {
            equal(format(invalid), "기록 시각 확인 필요");
        }
        TimeZone.setDefault(TimeZone.getTimeZone("America/Los_Angeles"));
        equal(format("2026-11-06T09:42:00.000000Z"), "11월 6일 01:42 기록");
        equal(format("2026-01-01T01:00:00Z"), "2025년 12월 31일 17:00 기록");
        Locale.setDefault(Locale.KOREA);
        equal(format("2026-11-06T09:42:00Z"), "11월 6일 01:42 기록");
        // The year decision is based on the device-local year, including New Year.
        Date newYear = Date.from(Instant.parse("2027-01-01T00:00:00Z"));
        equal(WidgetTimestamp.INSTANCE.format("2026-11-06T09:42:00Z", newYear), "11월 6일 01:42 기록");
        TimeZone.setDefault(TimeZone.getTimeZone("Asia/Seoul"));
        equal(WidgetTimestamp.INSTANCE.format("2026-11-06T09:42:00Z", newYear), "2026년 11월 6일 18:42 기록");
        System.out.println("PASS " + checks + " widget timestamp cases: Korean wording, timezone, fractions, invalid/empty cache, year boundaries");
    }
}
