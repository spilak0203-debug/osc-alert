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
    private com.google.android.material.floatingactionbutton.FloatingActionButton top;
    private final Map<Signals.Kind, StockAdapter.Section> headers = new EnumMap<>(Signals.Kind.class);

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
        // "Back to top" shows once the list is a few screens down.
        top = v.findViewById(R.id.to_top);
        lift();
        list.addOnScrollListener(new RecyclerView.OnScrollListener() {
            @Override
            public void onScrolled(@NonNull RecyclerView rv, int dx, int dy) {
                boolean far = lm.findFirstVisibleItemPosition() > 4;
                if (far) top.show(); else top.hide();
            }
        });
        top.setOnClickListener(x -> {
            // Jump close first so a long list doesn't animate through thousands of rows.
            if (lm.findFirstVisibleItemPosition() > 20) list.scrollToPosition(20);
            list.post(() -> list.smoothScrollToPosition(0));
            top.hide();
        });
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
            v.findViewById(R.id.sort_box).setVisibility(View.VISIBLE);
            com.google.android.material.chip.ChipGroup group = v.findViewById(R.id.sort);
            String current = Settings.sort(requireContext());
            for (int i = 0; i < Settings.SORTS.length; i++) {
                com.google.android.material.chip.Chip chip = new com.google.android.material.chip.Chip(
                        requireContext(), null, com.google.android.material.R.attr.chipStyle);
                chip.setText(Settings.SORT_LABELS[i]);
                chip.setTag(Settings.SORTS[i]);
                chip.setCheckable(true);
                chip.setCheckedIconVisible(false);
                chip.setId(View.generateViewId());
                group.addView(chip);
                if (Settings.SORTS[i].equals(current)) chip.setChecked(true);
            }
            group.setOnCheckedStateChangeListener((g, ids) -> {
                if (ids.isEmpty()) return;
                Settings.setSort(requireContext(), (String) g.findViewById(ids.get(0)).getTag());
                render();
                list.scrollToPosition(0);
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

    void lift() {
        if (top != null) top.animate().translationY(-MainActivity.buttonLift).setDuration(150).start();
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
            // Favourites lead each group; the sort is stable so the rest keep their order.
            java.util.Set<String> favs = Settings.favorites(requireContext());
            for (Map.Entry<Signals.Kind, List<Stock>> e : groups.entrySet()) {
                if (e.getValue().isEmpty()) continue;
                List<Stock> group = new ArrayList<>(e.getValue());
                java.util.Collections.sort(group, (a, b) ->
                        Boolean.compare(favs.contains(b.ticker), favs.contains(a.ticker)));
                e.setValue(group);
                StockAdapter.Section header = new StockAdapter.Section(e.getKey(), e.getValue().size());
                headers.put(e.getKey(), header);
                items.add(header);
                items.addAll(e.getValue());
            }
            String filter = Settings.filterSummary(requireContext());
            if (!filter.isEmpty()) s.append(s.length() > 0 ? "\n" : "").append("필터: ").append(filter).append(" · 설정 탭에서 변경");
        } else {
            // Filter and search first, then the chosen order. "favorite" keeps favourites in their
            // own group on top, each group by market cap.
            String sort = Settings.sort(requireContext());
            java.util.Set<String> favs = Settings.favorites(requireContext());
            List<Stock> shownStocks = new ArrayList<>();
            for (Stock st : stocks) {
                if (!Settings.passes(requireContext(), st)) continue;
                if (!query.isEmpty() && !st.name.toLowerCase(Locale.ROOT).contains(query) && !st.ticker.contains(query)) continue;
                shownStocks.add(st);
            }
            java.util.Collections.sort(shownStocks, order(sort));
            List<Object> starred = new ArrayList<>(), rest = new ArrayList<>();
            for (Stock st : shownStocks)
                (sort.equals("favorite") && favs.contains(st.ticker) ? starred : rest).add(st);
            int shown = starred.size() + rest.size();
            if (!starred.isEmpty()) {
                items.add("★ 즐겨찾기 · " + starred.size() + "종목");
                items.addAll(starred);
                if (!rest.isEmpty()) items.add("전체 종목 · " + rest.size() + "종목");
            }
            items.addAll(rest);
            String filter = Settings.filterSummary(requireContext());
            if (!filter.isEmpty()) s.append(s.length() > 0 ? "\n" : "").append("필터: ").append(filter).append(" · ").append(shown).append("종목");
            if (!query.isEmpty()) s.append(s.length() > 0 ? "\n" : "").append("검색 결과 ").append(shown).append("종목");
            else s.append(s.length() > 0 ? "\n" : "").append("길게 누르면 ")
                    .append(Settings.flag(requireContext(), Settings.COPY_NAME) ? "종목명" : "종목코드").append(" 복사");
        }
        status.setText(s);
        status.setVisibility(s.length() == 0 ? View.GONE : View.VISIBLE);
        adapter.submit(items);
    }

    /** Stocks without a value for the sort key go last; ties fall back to market cap. */
    private static java.util.Comparator<Stock> order(String sort) {
        java.util.Comparator<Stock> byCap = (a, b) -> Double.compare(nz(b.cap), nz(a.cap));
        switch (sort) {
            case "name":
                java.text.Collator ko = java.text.Collator.getInstance(Locale.KOREAN);
                return (a, b) -> ko.compare(a.name, b.name);
            case "code":
                return (a, b) -> a.ticker.compareTo(b.ticker);
            case "rise":
                return ((java.util.Comparator<Stock>) (a, b) -> Double.compare(nz(b.changePct()), nz(a.changePct())))
                        .thenComparing(byCap);
            case "fall":
                return ((java.util.Comparator<Stock>) (a, b) -> Double.compare(pz(a.changePct()), pz(b.changePct())))
                        .thenComparing(byCap);
            default:
                return byCap;
        }
    }

    private static double nz(double v) {
        return Double.isNaN(v) ? Double.NEGATIVE_INFINITY : v;
    }

    private static double pz(double v) {
        return Double.isNaN(v) ? Double.POSITIVE_INFINITY : v;
    }
}
