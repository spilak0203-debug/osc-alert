package kr.personal.oscalert;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.io.InputStream;
import java.nio.charset.StandardCharsets;

/** Rule.java must give the same answers as signal/rule.py (fixtures from tests/make_java_fixtures.py). */
public class RuleTest {
    static String resource(String name) throws Exception {
        try (InputStream in = RuleTest.class.getClassLoader().getResourceAsStream(name)) {
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    static double num(JSONObject o, String key) throws Exception {
        return o.isNull(key) ? Double.NaN : o.getDouble(key);
    }

    static Rule.Snap snap(JSONObject o) throws Exception {
        Rule.Snap s = new Rule.Snap();
        s.kFast = num(o, "k_fast"); s.dFast = num(o, "d_fast");
        s.kSlow = num(o, "k_slow"); s.dSlow = num(o, "d_slow");
        s.rsi = num(o, "rsi"); s.rsiSig = num(o, "rsi_sig"); s.cci = num(o, "cci");
        return s;
    }

    static Rule.Config config(JSONObject o) throws Exception {
        Rule.Config c = new Rule.Config();
        c.slow = !"fast".equals(o.optString("stoch", "slow"));
        c.stochBand = o.optBoolean("stoch_band", true);
        c.rsiBand = o.optBoolean("rsi_band", true);
        c.cciBand = o.optBoolean("cci_band", true);
        c.stochLo = o.optDouble("stoch_lo", 20); c.stochHi = o.optDouble("stoch_hi", 80);
        c.rsiLo = o.optDouble("rsi_lo", 30); c.rsiHi = o.optDouble("rsi_hi", 70);
        c.cciLevel = o.optDouble("cci_level", 100);
        return c;
    }

    static boolean[] bools(JSONArray a) throws Exception {
        boolean[] out = new boolean[a.length()];
        for (int i = 0; i < out.length; i++) out[i] = a.getBoolean(i);
        return out;
    }

    @Test
    public void matchesPython() throws Exception {
        JSONObject data = new JSONObject(resource("rule_cases.json"));
        JSONArray configs = data.getJSONArray("configs"), cases = data.getJSONArray("cases");
        assertTrue(cases.length() > 500);
        int fired = 0;
        for (int i = 0; i < cases.length(); i++) {
            JSONObject k = cases.getJSONObject(i);
            Rule.Config c = config(configs.getJSONObject(k.getInt("config")));
            Rule.Snap prev = snap(k.getJSONObject("prev")), last = snap(k.getJSONObject("last"));
            String where = "case " + i;
            assertArrayEquals(where, bools(k.getJSONArray("golden")), Rule.golden(prev, last, c));
            assertArrayEquals(where, bools(k.getJSONArray("dead")), Rule.dead(prev, last, c));
            JSONArray z = k.getJSONArray("zones");
            assertArrayEquals(where, new int[]{z.getInt(0), z.getInt(1)}, Rule.zones(last, c));
            fired += Rule.count(Rule.golden(prev, last, c)) == 3 ? 1 : 0;
        }
        assertTrue("fixture should contain full confluences", fired > 0);
    }

    @Test
    public void nanNeverFires() {
        Rule.Snap empty = new Rule.Snap();
        Rule.Config c = new Rule.Config();
        assertEquals(0, Rule.count(Rule.golden(empty, empty, c)));
        assertEquals(0, Rule.count(Rule.dead(empty, empty, c)));
        assertArrayEquals(new int[]{0, 0}, Rule.zones(empty, c));
    }
}
