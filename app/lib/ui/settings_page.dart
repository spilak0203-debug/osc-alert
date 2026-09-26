import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/rule.dart' as rule;
import '../core/settings.dart';
import '../platform/app_update.dart';
import '../platform/desktop.dart';
import '../platform/notifier.dart';
import 'toast.dart';

/// Alerts, stock filter, signal rules, display and app updates, each group in a card. Every
/// change saves immediately.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.controller});

  final ScrollController? controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

/// The settings page's groups, in order.
enum _Group {
  rules('신호 조건', Icons.tune),
  alerts('알림', Icons.notifications_outlined),
  filter('종목 필터', Icons.filter_alt_outlined),
  display('화면', Icons.palette_outlined),
  app('앱', Icons.info_outline);

  const _Group(this._label, this.icon);

  final String _label;
  final IconData icon;

  String label(bool desktop) => this == display && desktop ? '화면·PC' : _label;
}

class _SettingsPageState extends State<SettingsPage> {
  Release? _release;
  bool _checking = false;

  /// Every card starts folded to one summary line; these are the open ones.
  final _open = <_Group>{};

  Settings get st => Settings.I;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: st, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget sub(String text) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 2),
          child: Text(text, style: t.titleSmall!.copyWith(color: muted, fontWeight: FontWeight.w700)),
        );
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(text, style: t.bodyMedium),
        );
    final pairs = st.flag(Settings.pairSignals);

    final alerts = <Widget>[
      sub('받을 신호'),
      _toggle(Settings.alertCombo, '강도 높음 이상', '거래량 급증(전일 3배)·골든 교차${pairs ? '(2지표 이상)' : '(3지표)'}·이평선 밀집 돌파 중 2개면 높음, 3개면 매우 높음'),
      _toggle(Settings.alertMa, '이평선 밀집 돌파', '5·20·60·120일선이 1.5% 안에 모였다가 종가가 넷 다 위로 올라선 날'
          '${st.maRising == 'none' ? '' : ' (${Settings.maRisingLabels[st.maRising]} 상승 중)'}'),
      _toggle(Settings.alert3, '3지표 일치', '스토캐스틱·RSI·CCI가 모두 골든(또는 데드)크로스'),
      if (pairs) _toggle(Settings.alert2, '2지표 일치', '셋 중 둘만 일치해도 따로 알림'),
      _toggle(Settings.alertZoneIn, '과매도·과매수 진입', "'신호 조건'의 구간 판단 지표 수 이상이 구간에 새로 들어온 날"),
      _toggle(Settings.alertZoneOut, '과매도·과매수 탈출', '구간에 있던 지표가 빠져나온 날'),
      sub('보내는 방식'),
      _toggle(Settings.preMarket, '장 시작 전에도 알림', '다음 거래일 08시대에 같은 알림을 한 번 더'),
      _toggle(Settings.quietDays, '신호 없는 날에도 알림', '켜진 알림 종류에 맞는 종목이 없다는 알림'),
      label('소리'),
      _choice(
        st.sound,
        Platform.isAndroid
            ? const [['sound', '소리'], ['vibrate', '진동'], ['both', '소리+진동'], ['silent', '무음']]
            : const [['both', '소리'], ['silent', '무음']],
        (v) => st.setString(Settings.soundKey, v),
      ),
      _button('테스트 알림 보내기 (켜진 종류별 예시)', true, () async {
        if (!await Notifier.allowed()) {
          Toaster.show('알림 권한을 허용해야 합니다', long: true);
          await Notifier.askPermission();
          return;
        }
        final n = await Notifier.test();
        Toaster.show('테스트 알림 $n개를 보냈습니다');
      }),
    ];

    final filter = <Widget>[
      Text('요약·종목 탭·알림에 모두 적용됩니다', style: t.bodySmall!.copyWith(color: muted)),
      label('시장'),
      _choice(st.market, const [['all', '전체'], ['코스피', '코스피'], ['코스닥', '코스닥']],
          (v) => st.setString(Settings.filterMarket, v)),
      label('20일 평균 거래대금 최소'),
      _choice(_amount(Settings.filterDv), const [['0', '없음'], ['1', '1억'], ['5', '5억'], ['10', '10억'], ['50', '50억']],
          (v) => st.setNumber(Settings.filterDv, double.parse(v))),
      label('시가총액 최소'),
      _choice(_amount(Settings.filterCap),
          const [['0', '없음'], ['500', '500억'], ['1000', '1천억'], ['5000', '5천억'], ['10000', '1조']],
          (v) => st.setNumber(Settings.filterCap, double.parse(v))),
    ];

    final rules = <Widget>[
      sub('일치 판단'),
      _toggle(Settings.pairSignals, '2지표 일치도 신호로 보기',
          '켜면 셋 중 둘만 맞아도 골든·데드 신호. 끄면 스토캐스틱·RSI·CCI 셋이 모두 맞을 때만. 요약 분류·신호 강도·알림·차트에 모두 적용'),
      label('허용 기간 · 신호일과 그 앞 며칠 안에 교차하면 같이 센다'),
      _choice('${st.integer(Settings.windowKey)}', [for (var d = 0; d <= rule.maxWindow; d++) ['$d', d == 0 ? '당일' : '$d일']],
          (v) => st.setInteger(Settings.windowKey, int.parse(v))),
      label('과매도·과매수 구간 판단 지표 수 · 이 개수 이상이 구간에 있을 때'),
      _choice('${st.integer(Settings.zoneNeed)}', const [['1', '1개'], ['2', '2개'], ['3', '3개']],
          (v) => st.setInteger(Settings.zoneNeed, int.parse(v))),
      sub('스토캐스틱'),
      _choice(st.flag(Settings.stochSlow) ? 'slow' : 'fast', const [['slow', 'Slow 5-3-3'], ['fast', 'Fast 5-3']],
          (v) => st.setFlag(Settings.stochSlow, v == 'slow')),
      _toggle(Settings.stochBand, '밴드 조건 사용', '끄면 %K·%D가 교차하기만 하면 신호. 켜면 과매도 아래·과매수 위에서 교차할 때만'),
      _numbers(Settings.stochLo, '과매도', Settings.stochHi, '과매수'),
      sub('RSI (14 · 시그널 9)'),
      _toggle(Settings.rsiBand, '밴드 조건 사용', '끄면 RSI·시그널선이 교차하기만 하면 신호. 켜면 과매도 아래·과매수 위에서 교차할 때만'),
      _numbers(Settings.rsiLo, '과매도', Settings.rsiHi, '과매수'),
      sub('CCI (14)'),
      _toggle(Settings.cciBand, '밴드 조건 사용', '켜면 ±기준선 돌파, 끄면 0선 돌파'),
      _numbers(Settings.cciLevel, '기준선 (±)', null, null),
      sub('이평선 밀집 돌파'),
      label('장기선 상승 조건 · 고른 선이 5거래일 전보다 낮지 않을 때만 신호'),
      _choice(st.maRising, const [['both', '둘 다'], ['60', '60일선만'], ['120', '120일선만'], ['none', '안 봄']], (v) {
        st.setFlag(Settings.maUp60, v == 'both' || v == '60');
        st.setFlag(Settings.maUp120, v == 'both' || v == '120');
      }),
    ];
    final display = <Widget>[
      label('테마'),
      _choice(st.theme, const [['system', '기기 설정'], ['light', '라이트'], ['dark', '다크']],
          (v) => st.setString(Settings.themeKey, v)),
      label('글자 크기'),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          OutlinedButton(onPressed: () => _changeFont(-1), child: const Text('가−')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('${(st.fontScale * 100).round()}%', style: t.bodyLarge),
          ),
          OutlinedButton(onPressed: () => _changeFont(1), child: const Text('가+')),
        ]),
      ),
      label(Platform.isAndroid ? '종목을 길게 누르면 복사할 것' : '종목을 길게 누르거나 오른쪽 클릭하면 복사할 것'),
      _choice(st.flag(Settings.copyName) ? 'name' : 'code', const [['code', '종목코드'], ['name', '종목명']],
          (v) => st.setFlag(Settings.copyName, v == 'name')),
      if (Desktop.supported) ...[
        sub('PC'),
        _toggle(Settings.trayOnClose, '창을 닫으면 트레이로', '켜 두면 창을 닫아도 알림 확인을 계속합니다. 끝내려면 트레이 아이콘 메뉴의 종료'),
        _toggle(Settings.startWithWindows, '윈도우 시작 시 실행', '로그인하면 트레이에서 조용히 시작해 알림을 확인합니다',
            onChanged: Desktop.setStartWithWindows),
      ],
    ];

    final newer = AppUpdate.newer(_release);
    final app = <Widget>[
      Text('현재 버전 ${AppUpdate.versionName}${newer ? ' · 새 버전 ${_release!.name}' : ''}', style: t.bodyMedium),
      _button(newer ? '새 버전 설치' : '업데이트 확인', true, _checking ? null : () => _update(newer)),
      _button('버전 기록 보기', false, () => showChangelog(context)),
    ];

    // What each folded card says about itself.
    String onOff(String key) => st.flag(key) ? '켬' : '끔';
    String amount(String key, String none) {
      final v = st.prefs.getDouble(key) ?? 0;
      return v <= 0 ? none : '${v >= 10000 ? '${(v / 10000).toStringAsFixed(0)}조' : v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}천억' : '${v.toStringAsFixed(0)}억'}↑';
    }

    final window = st.integer(Settings.windowKey);
    final alertNames = [
      if (st.flag(Settings.alertCombo)) '강도 높음 이상',
      if (st.flag(Settings.alertMa)) '이평선 돌파',
      if (st.flag(Settings.alert3)) '3지표',
      if (pairs && st.flag(Settings.alert2)) '2지표',
      if (st.flag(Settings.alertZoneIn)) '과매도·과매수 진입',
      if (st.flag(Settings.alertZoneOut)) '과매도·과매수 탈출',
    ];
    final summaries = {
      _Group.rules: '${pairs ? '2지표도 신호' : '3지표만 신호'} · 허용 기간 ${window == 0 ? '당일' : '$window일'} · '
          '스토캐스틱 ${st.flag(Settings.stochSlow) ? 'Slow' : 'Fast'} · 밴드 조건 스토캐스틱 ${onOff(Settings.stochBand)}·'
          'RSI ${onOff(Settings.rsiBand)}·CCI ${onOff(Settings.cciBand)} · 이평선 돌파 장기선 ${Settings.maRisingLabels[st.maRising]}',
      _Group.alerts: alertNames.isEmpty ? '받을 알림 없음' : '받음: ${alertNames.join(' · ')}',
      _Group.filter: '${st.market == 'all' ? '전체 시장' : st.market} · 거래대금 ${amount(Settings.filterDv, '제한 없음')} · '
          '시총 ${amount(Settings.filterCap, '제한 없음')}',
      _Group.display: '테마 ${const {'system': '기기 설정', 'light': '라이트', 'dark': '다크'}[st.theme] ?? st.theme} · '
          '글자 ${(st.fontScale * 100).round()}% · 복사 ${st.flag(Settings.copyName) ? '종목명' : '종목코드'}'
          '${Desktop.supported ? ' · 트레이 ${onOff(Settings.trayOnClose)}' : ''}',
      _Group.app: '현재 버전 ${AppUpdate.versionName}${newer ? ' · 새 버전 ${_release!.name} 있음' : ''}',
    };
    final groups = {
      _Group.rules: rules,
      _Group.alerts: alerts,
      _Group.filter: filter,
      _Group.display: display,
      _Group.app: app,
    };
    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final e in groups.entries) _card(context, e.key, e.value, summaries[e.key]!),
            ]),
          ),
        ),
      ],
    );
  }

  /// One group in a card: icon and title, then its rows — or, folded, one line saying how it is set.
  Widget _card(BuildContext context, _Group g, List<Widget> children, String summary) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final open = _open.contains(g);
    return Card.filled(
      margin: const EdgeInsets.only(top: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => open ? _open.remove(g) : _open.add(g)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(g.icon, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(g.label(Desktop.supported), style: t.titleMedium!.copyWith(fontWeight: FontWeight.w700)),
                  if (!open)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(summary, style: t.bodySmall!.copyWith(color: cs.onSurfaceVariant)),
                    ),
                ]),
              ),
              Icon(open ? Icons.expand_less : Icons.expand_more, color: cs.onSurfaceVariant),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
      ]),
    );
  }

  Future<void> _update(bool newer) async {
    if (newer) {
      await AppUpdate.install(_release!);
      return;
    }
    setState(() => _checking = true);
    try {
      final r = await AppUpdate.latest();
      if (!mounted) return;
      setState(() => _release = r);
      if (!AppUpdate.newer(r)) Toaster.show('최신 버전입니다');
    } catch (e) {
      Toaster.show('확인 실패: $e', long: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _changeFont(int direction) {
    final now = st.fontScale;
    var next = ((now + direction * Settings.fontStep) * 10).round() / 10;
    next = next.clamp(Settings.fontMin, Settings.fontMax);
    if (next == now) {
      Toaster.show(direction > 0 ? '가장 큰 글자입니다' : '가장 작은 글자입니다');
      return;
    }
    st.setNumber(Settings.fontScaleKey, next);
    Toaster.show('글자 크기 ${(next * 100).round()}%');
  }

  String _amount(String key) => (st.prefs.getDouble(key) ?? 0).toStringAsFixed(0);

  Widget _toggle(String key, String title, String hint, {Future<void> Function(bool)? onChanged}) {
    final t = Theme.of(context).textTheme;
    final on = st.flag(key);
    void set(bool v) {
      st.setFlag(key, v);
      onChanged?.call(v);
    }

    return InkWell(
      onTap: () => set(!on),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.bodyLarge),
              Text(hint, style: t.bodySmall),
            ]),
          ),
          Switch(value: on, onChanged: set),
        ]),
      ),
    );
  }

  /// Segmented buttons; `save` receives the chosen option's value.
  Widget _choice(String current, List<List<String>> options, ValueChanged<String> save) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final o in options)
                ButtonSegment(value: o[0], label: Text(o[1], maxLines: 1, overflow: TextOverflow.fade, softWrap: false)),
            ],
            selected: {current},
            onSelectionChanged: (v) => save(v.first),
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
              visualDensity: VisualDensity.standard,
            ),
          ),
        ),
      );

  Widget _numbers(String keyA, String labelA, String? keyB, String? labelB) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          Expanded(child: _NumberField(key: ValueKey(keyA), settingKey: keyA, hint: labelA)),
          if (keyB != null) ...[
            const SizedBox(width: 12),
            Expanded(child: _NumberField(key: ValueKey(keyB), settingKey: keyB, hint: labelB!)),
          ],
        ]),
      );

  Widget _button(String text, bool filled, VoidCallback? onPressed) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: filled
            ? FilledButton(onPressed: onPressed, child: Text(text))
            : OutlinedButton(onPressed: onPressed, child: Text(text)),
      );
}

class _NumberField extends StatefulWidget {
  const _NumberField({super.key, required this.settingKey, required this.hint});

  final String settingKey, hint;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _c =
      TextEditingController(text: Settings.I.number(widget.settingKey).toStringAsFixed(0));
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          controller: _c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: widget.hint, border: const OutlineInputBorder(), errorText: _error),
          onChanged: (s) {
            final v = double.tryParse(s);
            if (v == null) {
              setState(() => _error = '숫자');
              return;
            }
            final cci = widget.settingKey == Settings.cciLevel;
            final ok = cci ? v > 0 && v <= 500 : v >= 0 && v <= 100;
            setState(() => _error = ok ? null : cci ? '1~500' : '0~100');
            if (ok) Settings.I.setNumber(widget.settingKey, v);
          },
        ),
      );
}

/// What changed in each version, newest first, from the bundled `assets/changelog.json`.
Future<void> showChangelog(BuildContext context) async {
  final entries = jsonDecode(await rootBundle.loadString('assets/changelog.json')) as List;
  if (!context.mounted) return;
  final t = Theme.of(context).textTheme;
  final cs = Theme.of(context).colorScheme;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('버전 기록'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 480,
        child: ListView(shrinkWrap: true, children: [
          for (final e in entries.cast<Map<String, dynamic>>()) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text.rich(TextSpan(children: [
                TextSpan(
                  text: e['version'] == null ? '이번 버전 ${AppUpdate.versionName}' : e['version'] as String,
                  style: t.titleSmall,
                ),
                TextSpan(
                  text: '  ${(e['date'] as String).replaceAll('-', '.')}',
                  style: t.bodySmall!.copyWith(color: cs.onSurfaceVariant),
                ),
              ])),
            ),
            for (final item in (e['items'] as List).cast<String>())
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('·  ', style: t.bodyMedium),
                  Expanded(child: Text(item, style: t.bodyMedium)),
                ]),
              ),
          ],
          const SizedBox(height: 8),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('닫기'))],
    ),
  );
}