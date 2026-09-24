package kr.personal.oscalert;

import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.EditText;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.fragment.app.Fragment;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout;

import java.util.ArrayList;
import java.util.EnumMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * The dashboard (`summary = true`: both indices, a tally per signal kind, then the stocks of each
 * kind) and the stocks tab (every stock, searchable). Rows expand into charts in both.
 */
public class ListFragment extends Fragment implements Repo.Listener {
    private static final String SUMMARY = "summary";

    private boolean summary;
    private StockAdapter adapter;
    private RecyclerView list;
    private SwipeRefreshLayout refresh;
    private TextView status;
    private View progress;
    private String query = "";
    private final Map<Signals.Kind, String> headers = new EnumMap<>(Signals.Kind.class);

    static ListFragment create(boolean summary) {
        ListFragment f = new ListFragment();
        Bundle b = new Bundle();
        b.putBoolean(SUMMARY, summary);
        f.setArguments(b);
        return f;
    }

    @Nullable
    @Override
    public View onCreateView(@NonNull LayoutInflater inf, @Nullable ViewGroup parent, @Nullable Bundle state) {
        summary = requireArguments().getBoolean(SUMMARY);
        View v = inf.inflate(R.layout.fragment_list, parent, false);
        status = v.findViewById(R.id.status);
        progress = v.findViewById(R.id.progress);
        refresh = v.findViewById(R.id.refresh);
        list = v.findViewById(R.id.list);
        LinearLayoutManager lm = new LinearLayoutManager(requireContext());
        list.setLayoutManager(lm);
        adapter = new StockAdapter();
        adapter.onJump(kind -> {
            int at = adapter.indexOf(headers.get(kind));
            if (at >= 0) lm.scrollToPositionWithOffset(at, 0);
        });
        list.setAdapter(adapter);
        refresh.setOnRefreshListener(() -> Repo.refresh(requireContext(), !summary));
        if (!summary) {
            v.findViewById(R.id.search_box).setVisibility(View.VISIBLE);
            EditText search = v.findViewById(R.id.search);
            search.addTextChangedListener(new TextWatcher() {
                @Override public void beforeTextChanged(CharSequence s, int a, int b, int c) { }
                @Override public void onTextChanged(CharSequence s, int a, int b, int c) { }
                @Override public void afterTextChanged(Editable s) {
                    query = s.toString().trim().toLowerCase(Locale.ROOT);
                    render();
                }
            });
        }
        return v;
    }

    @Override
    public void onStart() {
        super.onStart();
        Repo.listen(this);
        Repo.ensure(requireContext());
        render();
    }

    @Override
    public void onStop() {
        Repo.unlisten(this);
        super.onStop();
    }

    @Override
    public void onHiddenChanged(boolean hidden) {
        super.onHiddenChanged(hidden);
        if (hidden) return;
        render();
        // Opening the stocks tab for the first time fetches every price once.
        if (!summary && !Repo.wantAll) {
            Repo.wantAll = true;
            Repo.refresh(requireContext(), true);
        }
    }

    @Override
    public void onChanged() {
        if (isAdded()) render();
    }

    void render() {
        if (adapter == null) return;
        if (!Repo.loading) refresh.setRefreshing(false);
        progress.setVisibility(Repo.loading ? View.VISIBLE : View.GONE);
        List<Stock> stocks = Repo.stocks;
        List<Object> items = new ArrayList<>();
        StringBuilder s = new StringBuilder();
        if (!Repo.error.isEmpty()) s.append("불러오기 실패: ").append(Repo.error).append(" · 위의 새로고침을 눌러 보세요");
        if (stocks.isEmpty() && !Repo.loading && Repo.error.isEmpty()) s.append("아래로 당기거나 위의 새로고침을 누르세요");

        if (summary) {
            items.addAll(Repo.indices);
            Map<Signals.Kind, List<Stock>> groups = Signals.group(requireContext(), stocks);
            items.add(new StockAdapter.Counts(groups));
            headers.clear();
            for (Map.Entry<Signals.Kind, List<Stock>> e : groups.entrySet()) {
                if (e.getValue().isEmpty()) continue;
                String header = e.getKey().label + " · " + e.getValue().size() + "종목";
                headers.put(e.getKey(), header);
                items.add(header);
                items.addAll(e.getValue());
            }
            if (Settings.flag(requireContext(), Settings.LIQUID_ONLY)) {
                items.add("매수 쪽 신호는 20일 평균 거래대금 5억 이상만 표시합니다");
            }
        } else {
            int shown = 0;
            for (Stock st : stocks) {
                if (!query.isEmpty() && !st.name.toLowerCase(Locale.ROOT).contains(query) && !st.ticker.contains(query)) continue;
                items.add(st);
                shown++;
            }
            if (!query.isEmpty()) s.append(s.length() > 0 ? "\n" : "").append("검색 결과 ").append(shown).append("종목");
            else s.append(s.length() > 0 ? "\n" : "").append("길게 누르면 ")
                    .append(Settings.flag(requireContext(), Settings.COPY_NAME) ? "종목명" : "종목코드").append(" 복사");
        }
        status.setText(s);
        status.setVisibility(s.length() == 0 ? View.GONE : View.VISIBLE);
        adapter.submit(items);
    }
}
