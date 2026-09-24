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

import java.text.DateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * The summary tab (`summary = true`: signal stocks grouped by kind, tap opens Naver) and the
 * stocks tab (every stock, searchable, tap expands charts).
 */
public class ListFragment extends Fragment implements Repo.Listener {
    private static final String SUMMARY = "summary";

    private boolean summary;
    private StockAdapter adapter;
    private SwipeRefreshLayout refresh;
    private TextView status;
    private View progress;
    private String query = "";

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
        RecyclerView list = v.findViewById(R.id.list);
        list.setLayoutManager(new LinearLayoutManager(requireContext()));
        adapter = new StockAdapter(!summary);
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
        if (!hidden) {
            render();
            // Opening the stocks tab for the first time fetches every price once.
            if (!summary && Repo.quotesAt == 0) Repo.refresh(requireContext(), true);
        }
    }

    @Override
    public void onChanged() {
        if (isAdded()) render();
    }

    void render() {
        if (adapter == null) return;
        refresh.setRefreshing(false);
        progress.setVisibility(Repo.loading ? View.VISIBLE : View.GONE);
        List<Stock> stocks = Repo.stocks;
        List<Object> items = new ArrayList<>();
        StringBuilder s = new StringBuilder();
        if (!Repo.asof.isEmpty()) s.append(Repo.asof).append(" 종가 기준 신호 · ").append(stocks.size()).append("종목");
        if (Repo.quotesAt > 0) {
            s.append("\n시세 ").append(DateFormat.getTimeInstance(DateFormat.SHORT, Locale.KOREA).format(new Date(Repo.quotesAt)))
                    .append(" · 아래로 당겨 새로고침");
        }
        if (!Repo.error.isEmpty()) s.append("\n오류: ").append(Repo.error);
        if (stocks.isEmpty() && !Repo.loading && Repo.error.isEmpty()) s.append("아래로 당겨 불러오세요");

        if (summary) {
            Map<Signals.Kind, List<Stock>> groups = Signals.group(requireContext(), stocks);
            for (Map.Entry<Signals.Kind, List<Stock>> e : groups.entrySet()) {
                items.add(e.getKey().label + " · " + e.getValue().size());
                items.addAll(e.getValue());
            }
            if (Settings.flag(requireContext(), Settings.LIQUID_ONLY)) s.append("\n매수 쪽은 20일 평균 거래대금 5억 이상만");
        } else {
            int shown = 0;
            for (Stock st : stocks) {
                if (!query.isEmpty() && !st.name.toLowerCase(Locale.ROOT).contains(query) && !st.ticker.contains(query)) continue;
                items.add(st);
                shown++;
            }
            if (!query.isEmpty()) s.append("\n검색 결과 ").append(shown).append("종목");
        }
        status.setText(s);
        adapter.submit(items);
    }
}
