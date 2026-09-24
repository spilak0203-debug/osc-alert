package kr.personal.oscalert;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

/** Indicators.java must reproduce pandas (fixtures from tests/make_java_fixtures.py). */
public class IndicatorsTest {
    static double[] arr(JSONArray a) throws Exception {
        double[] out = new double[a.length()];
        for (int i = 0; i < out.length; i++) out[i] = a.isNull(i) ? Double.NaN : a.getDouble(i);
        return out;
    }

    static void same(String name, double[] want, double[] got) {
        int offset = got.length - want.length;
        for (int i = 0; i < want.length; i++) {
            double w = want[i], g = got[offset + i];
            if (Double.isNaN(w)) {
                assertTrue(name + " @" + i + " expected NaN, got " + g, Double.isNaN(g));
            } else {
                assertEquals(name + " @" + i, w, g, 1e-6 * Math.max(1, Math.abs(w)));
            }
        }
    }

    @Test
    public void matchesPandas() throws Exception {
        JSONObject data = new JSONObject(RuleTest.resource("indicator_series.json"));
        Indicators.Series s = Indicators.compute(arr(data.getJSONArray("high")),
                arr(data.getJSONArray("low")), arr(data.getJSONArray("close")));
        JSONObject e = data.getJSONObject("expected");
        same("k_fast", arr(e.getJSONArray("k_fast")), s.kFast);
        same("d_fast", arr(e.getJSONArray("d_fast")), s.dFast);
        same("k_slow", arr(e.getJSONArray("k_slow")), s.kSlow);
        same("d_slow", arr(e.getJSONArray("d_slow")), s.dSlow);
        same("rsi", arr(e.getJSONArray("rsi")), s.rsi);
        same("rsi_sig", arr(e.getJSONArray("rsi_sig")), s.rsiSig);
        same("cci", arr(e.getJSONArray("cci")), s.cci);
        for (int m = 0; m < Indicators.MA.length; m++) {
            String key = "ma" + Indicators.MA[m];
            same(key, arr(e.getJSONArray(key)), s.ma[m]);
        }
    }
}
