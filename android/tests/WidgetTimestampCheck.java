import com.kang88.carcar.WidgetTimestamp;
import java.text.DateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;

public class WidgetTimestampCheck {
    private static void equal(String actual, String expected) {
        if (!actual.equals(expected)) throw new AssertionError(actual + " != " + expected);
    }
    public static void main(String[] args) {
        Locale.setDefault(Locale.US);
        TimeZone.setDefault(TimeZone.getTimeZone("Asia/Seoul"));
        // UTC midnight becomes 09:00 on the device; fractional microseconds do not add minutes.
        String expected = "기록 " + DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT)
            .format(new Date(1793577600000L));
        equal(WidgetTimestamp.INSTANCE.format("2026-11-02T00:00:00.123456Z"), expected);
        equal(WidgetTimestamp.INSTANCE.format("2026-11-02T00:00:00Z"), expected);
        equal(WidgetTimestamp.INSTANCE.format("2026-11-02T00:00:00.123456+00:00"), expected);
        equal(WidgetTimestamp.INSTANCE.format("2026-11-02T09:00:00+09:00"), expected);
        equal(WidgetTimestamp.INSTANCE.format("2026-11-02T00:00:00.1Z"), expected);
        equal(WidgetTimestamp.INSTANCE.format("2026-02-30T00:00:00Z"), "기록 시각 확인 필요");
        equal(WidgetTimestamp.INSTANCE.format("2026-11-02T00:00:00Zgarbage"), "기록 시각 확인 필요");
        equal(WidgetTimestamp.INSTANCE.format(null), "기록 시각 확인 필요");
        equal(WidgetTimestamp.INSTANCE.format(""), "기록 시각 확인 필요");
        TimeZone.setDefault(TimeZone.getTimeZone("America/Los_Angeles"));
        expected = "기록 " + DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT)
            .format(new Date(1793577600000L));
        equal(WidgetTimestamp.INSTANCE.format("2026-11-02T00:00:00.000000Z"), expected);
        System.out.println("PASS 10 widget timestamp cases: locale/timezone, fractions, invalid/empty cache");
    }
}
