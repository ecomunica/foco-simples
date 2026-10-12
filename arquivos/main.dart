import 'dart:convert';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const navy = Color(0xFF173B83);
const blue = Color(0xFF2160C3);
const pale = Color(0xFFFCFDFF);

void main() => runApp(const FocoSimplesApp());

class FocoSimplesApp extends StatelessWidget {
  const FocoSimplesApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Foco Simples',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.white,
          colorScheme: ColorScheme.fromSeed(seedColor: navy),
          fontFamily: 'Roboto',
          appBarTheme: const AppBarTheme(backgroundColor: pale, foregroundColor: Color(0xFF15243D), elevation: 0),
        ),
        home: const FocusHome(),
      );
}

enum FocusStage { ready, running, paused, complete }

class FocusHome extends StatefulWidget {
  const FocusHome({super.key});
  @override
  State<FocusHome> createState() => _FocusHomeState();
}

class _FocusHomeState extends State<FocusHome> with WidgetsBindingObserver {
  static const MethodChannel sound =
      MethodChannel('br.com.qacom.foco_simples/alert');
  int totalSeconds = 25 * 60;
  int remainingSeconds = 25 * 60;
  FocusStage stage = FocusStage.ready;
  Timer? timer;
  DateTime? deadline;
  bool alreadyAlerted = false;
  String alertMode = 'sound'; // sound, vibrate, silent
  bool loaded = false;
  bool pomodoro = false;
  bool autoAdvance = true;
  int focusMinutes = 25;
  int shortBreakMinutes = 5;
  int longBreakMinutes = 15;
  int completedFocusInRound = 0;
  String phase = 'focus';
  String selectedProfile = 'Personalizado';
  List<Map<String, dynamic>> profiles = [
    {'name': 'Estudar', 'seconds': 1500, 'mode': 'sound'},
    {'name': 'Trabalhar', 'seconds': 3000, 'mode': 'sound'},
    {'name': 'Exercitar', 'seconds': 600, 'mode': 'vibrate'},
    {'name': 'Descansar', 'seconds': 300, 'mode': 'silent'},
  ];
  List<Map<String, dynamic>> history = [];
  int activeSessionId = 0;
  int countedSessionId = 0;

  bool _appBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreState();
  }

  Future<void> _restoreState() async {
    try {
      await _loadExtras();
      final data = await sound.invokeMapMethod<String, dynamic>('loadState');
      if (!mounted) return;
      if (data != null) {
        final duration = (data['total'] as num?)?.toInt() ?? 1500;
        final storedRemaining = (data['remaining'] as num?)?.toInt() ?? duration;
        final storedDeadline = (data['deadline'] as num?)?.toInt() ?? 0;
        final storedMode = data['stage'] as String? ?? 'ready';
        setState(() {
          totalSeconds = duration.clamp(1, 86400);
          remainingSeconds = storedRemaining.clamp(0, totalSeconds);
          alertMode = {'sound', 'vibrate', 'silent'}.contains(data['alertMode'])
              ? data['alertMode'] as String : 'sound';
          if (storedMode == 'running' && storedDeadline > 0) {
            deadline = DateTime.fromMillisecondsSinceEpoch(storedDeadline);
            remainingSeconds = ((deadline!.difference(DateTime.now()).inMilliseconds / 1000).ceil())
                .clamp(0, totalSeconds);
            stage = remainingSeconds == 0 ? FocusStage.complete : FocusStage.running;
            alreadyAlerted = remainingSeconds == 0;
          } else {
            stage = FocusStage.values.firstWhere(
              (e) => e.name == storedMode, orElse: () => FocusStage.ready);
            if (stage == FocusStage.running) stage = FocusStage.paused;
            alreadyAlerted = stage == FocusStage.complete;
          }
        });
        if (stage == FocusStage.running) {
          timer = Timer.periodic(const Duration(milliseconds: 250), (_) => refreshTimer());
        }
        if (stage == FocusStage.complete) {
          _onSessionCompleted(recovered: true);
          _persist(); // Terminado enquanto app estava fechado.
        }
      }
    } catch (_) {
      // O cronômetro permanece utilizável caso a ponte Android esteja indisponível.
    } finally {
      if (mounted) setState(() => loaded = true);
    }
  }


  Future<void> _loadExtras() async {
    final raw = await sound.invokeMethod<String>('loadExtras');
    if (raw == null || raw.isEmpty) return;
    final value = jsonDecode(raw);
    if (value is! Map) return;
    pomodoro = value['pomodoro'] == true;
    autoAdvance = value['autoAdvance'] != false;
    focusMinutes = ((value['focusMinutes'] as num?)?.toInt() ?? 25).clamp(1, 1440);
    shortBreakMinutes = ((value['shortBreakMinutes'] as num?)?.toInt() ?? 5).clamp(1, 1440);
    longBreakMinutes = ((value['longBreakMinutes'] as num?)?.toInt() ?? 15).clamp(1, 1440);
    completedFocusInRound = ((value['completedFocusInRound'] as num?)?.toInt() ?? 0).clamp(0, 4);
    phase = value['phase'] == 'short' || value['phase'] == 'long' ? value['phase'] as String : 'focus';
    selectedProfile = value['selectedProfile'] as String? ?? 'Personalizado';
    activeSessionId = (value['activeSessionId'] as num?)?.toInt() ?? 0;
    countedSessionId = (value['countedSessionId'] as num?)?.toInt() ?? 0;
    if (value['profiles'] is List) {
      profiles = (value['profiles'] as List).whereType<Map>().map((e) =>
        {'name': (e['name'] ?? '').toString(),
         'seconds': ((e['seconds'] as num?)?.toInt() ?? 1500).clamp(1,86400),
         'mode': (e['mode'] ?? 'sound').toString()}).where((e) =>
           (e['name'] as String).isNotEmpty).take(16).toList();
    }
    if (value['history'] is List) {
      history = (value['history'] as List).whereType<Map>().map((e) =>
        {'day': (e['day'] ?? '').toString(),
         'seconds': ((e['seconds'] as num?)?.toInt() ?? 0).clamp(0,86400),
         'label': (e['label'] ?? 'Foco').toString()}).take(500).toList();
    }
  }

  Future<void> _saveExtras() async {
    try {
      await sound.invokeMethod<void>('saveExtras', jsonEncode({
        'pomodoro':pomodoro, 'autoAdvance':autoAdvance,
        'focusMinutes':focusMinutes, 'shortBreakMinutes':shortBreakMinutes,
        'longBreakMinutes':longBreakMinutes,
        'completedFocusInRound':completedFocusInRound, 'phase':phase,
        'selectedProfile':selectedProfile, 'profiles':profiles,
        'history':history, 'activeSessionId':activeSessionId,
        'countedSessionId':countedSessionId,
      }));
    } catch (_) {}
  }

  void _onSessionCompleted({bool recovered = false}) {
    if (activeSessionId == 0 || activeSessionId == countedSessionId) return;
    countedSessionId = activeSessionId;
    if (!pomodoro || phase == 'focus') {
      final today = DateTime.now();
      final day = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
      history.insert(0, {'day':day,'seconds':totalSeconds,
        'label':pomodoro ? 'Pomodoro' : selectedProfile});
      if (history.length > 500) history.removeRange(500,history.length);
      if (pomodoro) completedFocusInRound = (completedFocusInRound + 1).clamp(0,4);
    }
    // No advance while app is closed: the next phase is prepared when opened.
    if (pomodoro) {
      if (phase == 'focus') {
        phase = completedFocusInRound >= 4 ? 'long' : 'short';
      } else {
        if (phase == 'long') completedFocusInRound = 0;
        phase = 'focus';
      }
    }
    _saveExtras();
  }

  String get phaseName => phase == 'focus' ? 'Concentração' :
    phase == 'long' ? 'Pausa longa' : 'Pausa curta';

  void _prepareNextPomodoro() {
    if (!pomodoro) return;
    final seconds = (phase == 'focus' ? focusMinutes :
      phase == 'long' ? longBreakMinutes : shortBreakMinutes) * 60;
    setState(() { totalSeconds = seconds; remainingSeconds = seconds;
      stage = FocusStage.ready; alreadyAlerted = false; deadline = null; });
    _persist(); _saveExtras();
  }

  Future<void> _openProfiles() async {
    if (stage == FocusStage.running) toggleTimer();
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (context) =>
      ProfileScreen(profiles: profiles, onSelect: (profile) {
        final secs = (profile['seconds'] as num).toInt();
        timer?.cancel(); deadline = null;
        setState(() { pomodoro = false; selectedProfile = profile['name'] as String;
          alertMode = profile['mode'] as String; totalSeconds = secs;
          remainingSeconds = secs; stage = FocusStage.ready; alreadyAlerted = false; });
        _cancelBackgroundAlert(); _persist(); _saveExtras();
      }, onSave: (list) { profiles = list; _saveExtras(); })));
    if (mounted) setState(() {});
  }

  Future<void> _openPomodoro() async {
    if (stage == FocusStage.running) toggleTimer();
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => PomodoroScreen(
        enabled: pomodoro, focus: focusMinutes, shortBreak: shortBreakMinutes,
        longBreak: longBreakMinutes, autoAdvance: autoAdvance)));
    if (result == null || !mounted) return;
    timer?.cancel(); deadline = null;
    setState(() {
      pomodoro = result['enabled'] as bool;
      autoAdvance = result['autoAdvance'] as bool;
      focusMinutes = result['focus'] as int;
      shortBreakMinutes = result['short'] as int;
      longBreakMinutes = result['long'] as int;
      phase = 'focus'; completedFocusInRound = 0;
      if (pomodoro) { totalSeconds = focusMinutes * 60; selectedProfile = 'Pomodoro'; }
      remainingSeconds = totalSeconds; stage = FocusStage.ready; alreadyAlerted = false;
    });
    _cancelBackgroundAlert(); _persist(); _saveExtras();
  }

  void _openStatistics() => Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => StatisticsScreen(history: List.of(history))));

  Future<void> _persist() async {
    try {
      await sound.invokeMethod<void>('saveState', <String, Object>{
        'total': totalSeconds,
        'remaining': remainingSeconds,
        'deadline': stage == FocusStage.running
            ? (deadline?.millisecondsSinceEpoch ?? 0) : 0,
        'stage': stage.name,
        'alertMode': alertMode,
      });
    } catch (_) {}
  }

  Future<void> _cancelBackgroundAlert() async {
    try { await sound.invokeMethod<void>('cancelCompletion'); } catch (_) {}
  }

  Future<void> _scheduleBackgroundAlert() async {
    if (stage != FocusStage.running || deadline == null) return;
    await _persist();
    try {
      await sound.invokeMethod<void>('scheduleCompletion', <String, Object>{
        'deadline': deadline!.millisecondsSinceEpoch,
        'alertMode': alertMode,
      });
    } catch (_) {}
  }

  Future<void> _selectAlertMode() async {
    final chosen = await showModalBottomSheet<String>(context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 5, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Aviso ao finalizar', style: TextStyle(fontSize: 20,
            fontWeight: FontWeight.bold, color: navy)),
          const SizedBox(height: 12),
          for (final option in const <(String, IconData, String)>[
            ('sound', Icons.notifications_active_rounded, 'Som curto'),
            ('vibrate', Icons.vibration_rounded, 'Somente vibração'),
            ('silent', Icons.notifications_off_outlined, 'Silencioso'),
          ]) ListTile(
            leading: Icon(option.$2, color: blue),
            title: Text(option.$3),
            trailing: alertMode == option.$1 ? const Icon(Icons.check, color: blue) : null,
            onTap: () => Navigator.pop(context, option.$1),
          ),
          const Text('Notificações em segundo plano dependem da permissão e das regras de bateria do Android.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
        ]))),
    );
    if (!mounted || chosen == null) return;
    setState(() => alertMode = chosen);
    await _persist();
    if (_appBackground) await _scheduleBackgroundAlert();
  }

  String printDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return hours > 0
        ? '${two(hours)}:${two(minutes)}:${two(secs)}'
        : '${two(minutes)}:${two(secs)}';
  }

  void refreshTimer() {
    if (!mounted || stage != FocusStage.running || deadline == null) return;
    final next = (deadline!.difference(DateTime.now()).inMilliseconds / 1000)
        .ceil()
        .clamp(0, totalSeconds);
    if (next > 0) {
      if (next != remainingSeconds) setState(() => remainingSeconds = next);
      return;
    }
    timer?.cancel();
    _onSessionCompleted();
    deadline = null;
    setState(() {
      remainingSeconds = 0;
      stage = FocusStage.complete;
    });
    _cancelBackgroundAlert();
    _persist();
    if (pomodoro && autoAdvance && !_appBackground) {
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted || stage != FocusStage.complete || _appBackground) return;
        _prepareNextPomodoro();
        toggleTimer();
      });
    }
    if (!alreadyAlerted) {
      alreadyAlerted = true;
      if (alertMode == 'sound') {
        sound.invokeMethod<void>('playCompletionSound').catchError((Object _) {
          return SystemSound.play(SystemSoundType.alert);
        });
      } else if (alertMode == 'vibrate') {
        sound.invokeMethod<void>('vibrateCompletion').catchError((Object _) {
          return HapticFeedback.mediumImpact();
        });
      }
    }
  }

  void toggleTimer() {
    if (stage == FocusStage.running) {
      refreshTimer();
      if (stage != FocusStage.running) return;
      timer?.cancel();
      deadline = null;
      setState(() => stage = FocusStage.paused);
      _cancelBackgroundAlert();
      _persist();
    } else {
      if (remainingSeconds == 0) remainingSeconds = totalSeconds;
      if (stage != FocusStage.paused) {
        activeSessionId = DateTime.now().microsecondsSinceEpoch;
        _saveExtras();
      }
      deadline = DateTime.now().add(Duration(seconds: remainingSeconds));
      setState(() => stage = FocusStage.running);
      timer?.cancel();
      timer = Timer.periodic(const Duration(milliseconds: 250), (_) => refreshTimer());
      _persist();
      // Android 13+ asks for permission once; if denied, in-app alert still works.
      sound.invokeMethod<void>('requestNotificationPermission').catchError((Object _) {});
    }
  }

  void resetTimer() {
    timer?.cancel();
    deadline = null;
    setState(() {
      stage = FocusStage.ready;
      remainingSeconds = totalSeconds;
      alreadyAlerted = false;
    });
    _cancelBackgroundAlert();
    _persist();
  }

  Future<void> changeDuration() async {
    // Opening the picker pauses the countdown; canceling resumes it.
    final wasRunning = stage == FocusStage.running;
    if (wasRunning) toggleTimer();
    final selected = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => DurationScreen(initial: totalSeconds)),
    );
    if (!mounted) return;
    if (selected != null) {
      timer?.cancel();
      deadline = null;
      setState(() {
        totalSeconds = selected;
        remainingSeconds = selected;
        stage = FocusStage.ready;
        pomodoro = false; selectedProfile = 'Personalizado';
        alreadyAlerted = false;
      });
      _saveExtras();
      _cancelBackgroundAlert();
      _persist();
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => DurationConfirmed(duration: selected)));
    } else if (wasRunning && stage == FocusStage.paused) {
      toggleTimer();
    }
  }

  Future<void> _resumeFromBackground() async {
    await _cancelBackgroundAlert();
    try {
      final state = await sound.invokeMapMethod<String, dynamic>('loadState');
      if (!mounted) return;
      // Se o Android entregou a notificação, não toca o alerta novamente.
      if (state?['stage'] == 'complete' && stage == FocusStage.running) {
        timer?.cancel();
        deadline = null;
        alreadyAlerted = true;
        _onSessionCompleted(recovered: true);
        setState(() {
          remainingSeconds = 0;
          stage = FocusStage.complete;
        });
        return;
      }
    } catch (_) {}
    refreshTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appBackground = false;
      _resumeFromBackground();
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.hidden) {
      _appBackground = true;
      _scheduleBackgroundAlert();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Foco Simples', style: TextStyle(fontWeight: FontWeight.w600)),
          centerTitle: true,
          backgroundColor: pale,
          actions: [IconButton(
            tooltip: 'Estatísticas', icon: const Icon(Icons.bar_chart_rounded),
            onPressed: _openStatistics), IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Configurar alerta',
            onPressed: _selectAlertMode,
          )],
        ),
        body: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                      child: stage == FocusStage.complete
                          ? _completed()
                          : _timerScreen(),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      );

  Widget _timerScreen() {
    final isRunning = stage == FocusStage.running;
    final progress = (totalSeconds - remainingSeconds) / totalSeconds;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const SizedBox(height: 12),
      Text(pomodoro ? '$phaseName • ${completedFocusInRound.clamp(0,4)}/4 focos' : 'Um momento para se concentrar',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18, color: Color(0xFF26354C))),
      const SizedBox(height: 25),
      LayoutBuilder(builder: (context, bounds) {
        final size = bounds.maxWidth.clamp(0.0, 310.0);
        return SizedBox(width: size, height: size,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(child: CircularProgressIndicator(
              value: stage == FocusStage.ready ? 0.72 : 1 - progress,
              strokeWidth: 9, strokeCap: StrokeCap.round,
              backgroundColor: const Color(0xFFE7EDF8),
              valueColor: const AlwaysStoppedAnimation(blue),
            )),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Image.asset('assets/icone.png', width: 48, height: 48,
                semanticLabel: 'Ícone Foco Simples'),
              const SizedBox(height: 12),
              FittedBox(fit: BoxFit.scaleDown, child: Text(printDuration(remainingSeconds),
                style: TextStyle(color: navy, fontWeight: FontWeight.bold,
                  fontSize: totalSeconds >= 3600 ? 42 : 53))),
              if (stage == FocusStage.ready) ...[
                const SizedBox(height: 8),
                Text(pomodoro ? phaseName : selectedProfile,
                  style: TextStyle(color: blue, fontSize: 12)),
              ],
            ]),
          ]));
      }),
      const SizedBox(height: 24),
      SizedBox(width: double.infinity, child: FilledButton.icon(
        onPressed: toggleTimer,
        icon: Icon(isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded),
        label: Text(isRunning ? 'Pausar' : stage == FocusStage.paused ? 'Continuar' : 'Iniciar'),
        style: actionStyle,
      )),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton.icon(
          onPressed: changeDuration, icon: const Icon(Icons.schedule_rounded, size: 19),
          label: const FittedBox(child: Text('Alterar tempo')),
          style: secondaryStyle,
        )),
        const SizedBox(width: 10),
        Expanded(child: OutlinedButton.icon(
          onPressed: resetTimer, icon: const Icon(Icons.restart_alt_rounded, size: 19),
          label: const FittedBox(child: Text('Reiniciar')),
          style: secondaryStyle,
        )),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: _openPomodoro,
          icon: const Icon(Icons.autorenew_rounded, size: 19),
          label: const Text('Pomodoro'), style: secondaryStyle)),
        const SizedBox(width: 10),
        Expanded(child: OutlinedButton.icon(onPressed: _openProfiles,
          icon: const Icon(Icons.bookmark_rounded, size: 19),
          label: const Text('Perfis'), style: secondaryStyle)),
      ]),
      const SizedBox(height: 18),
      Text('Aviso: ${alertMode == 'sound' ? 'som curto' : alertMode == 'vibrate' ? 'vibração' : 'silencioso'}',
        style: const TextStyle(fontSize: 12, color: Color(0xFF60708D))),
      const SizedBox(height: 12),
      const _Footer(),
    ]);
  }

  Widget _completed() => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const SizedBox(height: 26),
    Container(width: 148, height: 148,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE6EEFF)),
      child: const Icon(Icons.notifications_active_rounded, size: 78, color: blue)),
    const SizedBox(height: 18),
    const Text('00:00', style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold,
      color: navy)),
    const SizedBox(height: 9),
    const Text('Tempo concluído!', style: TextStyle(fontSize: 27,
      fontWeight: FontWeight.bold, color: Color(0xFF17253D))),
    const SizedBox(height: 15),
    const Text('Ótimo trabalho!\nQue tal fazer uma pausa ou\niniciar um novo foco?',
      textAlign: TextAlign.center, style: TextStyle(fontSize: 17, height: 1.5,
        color: Color(0xFF56647B))),
    const SizedBox(height: 32),
    SizedBox(width: double.infinity, child: FilledButton.icon(
      onPressed: () { resetTimer(); toggleTimer(); },
      icon: const Icon(Icons.play_arrow_rounded), label: const Text('Iniciar novamente'),
      style: actionStyle)),
    const SizedBox(height: 12),
    SizedBox(width: double.infinity, child: OutlinedButton.icon(
      onPressed: changeDuration, icon: const Icon(Icons.schedule_rounded),
      label: const Text('Definir outro tempo'), style: secondaryStyle)),
    const SizedBox(height: 34), const _Footer(),
  ]);

}

final actionStyle = FilledButton.styleFrom(
  backgroundColor: navy,
  foregroundColor: Colors.white,
  minimumSize: const Size(0, 53),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
);
final secondaryStyle = OutlinedButton.styleFrom(
  foregroundColor: navy,
  minimumSize: const Size(0, 53),
  side: const BorderSide(color: Color(0xFF9AAAC7)),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
);

class _Footer extends StatelessWidget {
  const _Footer();
  @override
  Widget build(BuildContext context) => const Text(
    'Até 24 horas  •  Sem login  •  Sem anúncios  •  Offline',
    textAlign: TextAlign.center,
    style: TextStyle(color: Color(0xFF60708D), fontSize: 12));
}

class DurationScreen extends StatefulWidget {
  const DurationScreen({super.key, required this.initial});
  final int initial;
  @override
  State<DurationScreen> createState() => _DurationScreenState();
}

class _DurationScreenState extends State<DurationScreen> {
  late int hours, minutes, seconds;
  late FixedExtentScrollController hc, mc, sc;
  @override
  void initState() {
    super.initState();
    hours = widget.initial ~/ 3600;
    minutes = (widget.initial % 3600) ~/ 60;
    seconds = widget.initial % 60;
    hc = FixedExtentScrollController(initialItem: hours);
    mc = FixedExtentScrollController(initialItem: minutes);
    sc = FixedExtentScrollController(initialItem: seconds);
  }

  void preset(int value) {
    final h = value ~/ 3600;
    final m = (value % 3600) ~/ 60;
    final s = value % 60;
    setState(() { hours = h; minutes = m; seconds = s; });
    hc.jumpToItem(h); mc.jumpToItem(m); sc.jumpToItem(s);
  }

  @override
  void dispose() { hc.dispose(); mc.dispose(); sc.dispose(); super.dispose(); }

  String two(int n) => n.toString().padLeft(2, '0');
  Widget wheel(String title, int count, int selected,
      FixedExtentScrollController controller, ValueChanged<int> onChanged) {
    return Expanded(child: Column(children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w600,
        fontSize: 12, color: Color(0xFF26354C))),
      const SizedBox(height: 9),
      Container(height: 188,
        decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E6F2))),
        // O destaque deve ficar ATRÁS dos números. Antes, o Container
        // em selectionOverlay era pintado sobre o valor selecionado,
        // tornando o número central invisível.
        child: Stack(children: [
          Positioned.fill(child: Center(child: Container(
            height: 39,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFE5F0FF),
              borderRadius: BorderRadius.circular(11)),
          ))),
          CupertinoPicker(
            backgroundColor: Colors.transparent,
            scrollController: controller,
            itemExtent: 39,
            selectionOverlay: null,
            onSelectedItemChanged: onChanged,
            children: List.generate(count, (i) => Center(child: Text(two(i),
              style: TextStyle(color: i == selected ? navy : const Color(0xFF8B98AA),
                fontSize: i == selected ? 22 : 17,
                fontWeight: i == selected ? FontWeight.bold : FontWeight.normal)))),
          ),
        ]),
      ),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    final value = hours * 3600 + minutes * 60 + seconds;
    final valid = value >= 1 && value <= 86400;
    const presets = <(String, int)>[
      ('5 min', 300), ('10 min', 600), ('25 min', 1500),
      ('50 min', 3000), ('1 hora', 3600), ('2 horas', 7200),
    ];
    return Scaffold(backgroundColor: pale,
      appBar: AppBar(title: const Text('Definir tempo')),
      body: SafeArea(child: LayoutBuilder(builder: (context, limits) =>
        SingleChildScrollView(child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: limits.maxHeight),
          child: Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(padding: const EdgeInsets.fromLTRB(22, 30, 22, 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Escolha o tempo', style: TextStyle(fontSize: 25,
                  color: Color(0xFF17253D), fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                const Text('Selecione horas, minutos e segundos.',
                  style: TextStyle(color: Color(0xFF6B788E), fontSize: 14)),
                const SizedBox(height: 26),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  wheel('Horas', 25, hours, hc, (n) {
                    setState(() {
                      hours = n;
                      if (n == 24) { minutes = 0; seconds = 0; }
                    });
                    if (n == 24) { mc.jumpToItem(0); sc.jumpToItem(0); }
                  }),
                  const SizedBox(width: 9),
                  wheel('Minutos', 60, minutes, mc, (n) {
                    setState(() {
                      minutes = n;
                      if (hours == 24 && n != 0) hours = 23;
                    });
                    if (hours == 23 && n != 0 && hc.selectedItem == 24) hc.jumpToItem(23);
                  }),
                  const SizedBox(width: 9),
                  wheel('Segundos', 60, seconds, sc, (n) {
                    setState(() {
                      seconds = n;
                      if (hours == 24 && n != 0) hours = 23;
                    });
                    if (hours == 23 && n != 0 && hc.selectedItem == 24) hc.jumpToItem(23);
                  }),
                ]),
                const SizedBox(height: 12),
                const Text('Limite máximo: 24 horas (24:00:00)',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF748098), fontSize: 12)),
                const SizedBox(height: 26),
                const Text('Atalhos rápidos', style: TextStyle(
                  color: Color(0xFF17253D), fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                const Text('Escolha um tempo comum ou defina manualmente.',
                  style: TextStyle(color: Color(0xFF6B788E), fontSize: 12)),
                const SizedBox(height: 15),
                LayoutBuilder(builder: (context, c) {
                  final gap = 9.0;
                  final w = (c.maxWidth - 2 * gap) / 3;
                  return Wrap(spacing: gap, runSpacing: 9, children: [
                    for (final entry in presets)
                      SizedBox(width: w, height: 49, child: OutlinedButton(
                        onPressed: () => preset(entry.$2),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: value == entry.$2 ? navy : Colors.white,
                          foregroundColor: value == entry.$2 ? Colors.white : navy,
                          side: BorderSide(color: value == entry.$2
                            ? navy : const Color(0xFFD3DCEB)),
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
                        child: Text(entry.$1, style: const TextStyle(fontSize: 14)))),
                  ]);
                }),
                const SizedBox(height: 25),
                Container(padding: const EdgeInsets.all(17),
                  decoration: BoxDecoration(color: const Color(0xFFEDF4FF),
                    borderRadius: BorderRadius.circular(17)),
                  child: Row(children: [
                    const CircleAvatar(backgroundColor: Color(0xFFDBE9FF),
                      child: Icon(Icons.schedule_rounded, color: blue)),
                    const SizedBox(width: 13),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Tempo selecionado', style: TextStyle(
                        color: Color(0xFF51627F), fontSize: 12)),
                      Text('${two(hours)}:${two(minutes)}:${two(seconds)}',
                        style: const TextStyle(color: navy, fontWeight: FontWeight.bold,
                          fontSize: 25)),
                    ]),
                  ])),
                if (!valid) const Padding(padding: EdgeInsets.only(top: 9),
                  child: Text('Selecione de 1 segundo a 24 horas.',
                    style: TextStyle(color: Color(0xFFB3261E)))),
                const SizedBox(height: 16),
                FilledButton(onPressed: valid ? () {
                  Navigator.of(context).pop(value);
                  // A confirmação é exibida por quem iniciou a configuração.
                } : null, style: actionStyle, child: const Text('Definir')),
              ]),
            ),
          )),
        )),
      )),
    );
  }
}

class DurationConfirmed extends StatelessWidget {
  const DurationConfirmed({super.key, required this.duration});
  final int duration;
  @override
  Widget build(BuildContext context) {
    final h = duration ~/ 3600;
    final m = (duration % 3600) ~/ 60;
    final s = duration % 60;
    String f(int n) => n.toString().padLeft(2, '0');
    return Scaffold(backgroundColor: pale, appBar: AppBar(title: const Text('Definir tempo')),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(padding: const EdgeInsets.all(25),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 130, height: 130,
              decoration: const BoxDecoration(shape: BoxShape.circle,
                color: Color(0xFFDDFBED)),
              child: const Icon(Icons.check_rounded, color: Color(0xFF18A56B), size: 75)),
            const SizedBox(height: 32),
            const Text('Tempo definido!', style: TextStyle(color: Color(0xFF17253D),
              fontSize: 27, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Text('O cronômetro foi configurado\npara ${f(h)}:${f(m)}:${f(s)}.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, height: 1.4,
                color: Color(0xFF58677C))),
            const SizedBox(height: 80),
            SizedBox(width: double.infinity, child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: actionStyle, child: const Text('Voltar ao cronômetro'))),
          ]),
        ),
      ))),
    );
  }
}

class PomodoroScreen extends StatefulWidget {
  const PomodoroScreen({super.key, required this.enabled, required this.focus,
    required this.shortBreak, required this.longBreak, required this.autoAdvance});
  final bool enabled, autoAdvance;
  final int focus, shortBreak, longBreak;
  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen> {
  late bool enabled, automatic;
  late int focus, shortBreak, longBreak;
  @override
  void initState() {
    super.initState();
    enabled = widget.enabled; automatic = widget.autoAdvance;
    focus = widget.focus; shortBreak = widget.shortBreak; longBreak = widget.longBreak;
  }

  Widget setting(String label, int value, ValueChanged<int> onChange) =>
    Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 16, color: navy))),
      IconButton(onPressed: value > 1 ? () => onChange(value - 1) : null,
        icon: const Icon(Icons.remove_circle_outline, color: blue)),
      Text('$value min', style: const TextStyle(fontWeight: FontWeight.bold, color: navy)),
      IconButton(onPressed: value < 1440 ? () => onChange(value + 1) : null,
        icon: const Icon(Icons.add_circle_outline, color: blue)),
    ]));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Modo Pomodoro')),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: ListView(padding: const EdgeInsets.all(20), children: [
        const Icon(Icons.autorenew_rounded, color: blue, size: 62),
        const SizedBox(height: 10),
        const Text('Concentração e pausas', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 23, color: navy, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        SwitchListTile(title: const Text('Ativar Pomodoro'), value: enabled,
          onChanged: (v) => setState(() => enabled = v)),
        setting('Foco', focus, (n) => setState(() => focus = n)),
        setting('Pausa curta', shortBreak, (n) => setState(() => shortBreak = n)),
        setting('Pausa longa', longBreak, (n) => setState(() => longBreak = n)),
        const SizedBox(height: 8),
        SwitchListTile(title: const Text('Iniciar a próxima etapa automaticamente'),
          subtitle: const Text('Enquanto o aplicativo estiver em primeiro plano.'),
          value: automatic, onChanged: (v) => setState(() => automatic = v)),
        const SizedBox(height: 8),
        const Text('Após quatro focos, acontece uma pausa longa. '
          'Ao voltar de segundo plano, confirme a próxima etapa no app.',
          style: TextStyle(color: Color(0xFF56647B))),
        const SizedBox(height: 25),
        FilledButton(style: actionStyle, onPressed: () => Navigator.pop(context,
          {'enabled':enabled, 'autoAdvance':automatic, 'focus':focus,
           'short':shortBreak, 'long':longBreak}),
          child: const Text('Salvar configuração')),
      ]),
    ))),
  );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.profiles,
    required this.onSelect, required this.onSave});
  final List<Map<String, dynamic>> profiles;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final ValueChanged<List<Map<String, dynamic>>> onSave;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late List<Map<String, dynamic>> profiles;
  @override
  void initState() { super.initState();
    profiles = widget.profiles.map((e) => Map<String,dynamic>.of(e)).toList();
  }

  Future<void> edit([int? index]) async {
    final name = TextEditingController(text: index == null ? '' : profiles[index]['name'] as String);
    final minutes = TextEditingController(text: index == null ? '25' :
      (((profiles[index]['seconds'] as int) / 60).ceil()).toString());
    String mode = index == null ? 'sound' : profiles[index]['mode'] as String;
    final result = await showDialog<Map<String,dynamic>>(context: context,
      builder: (dialog) => StatefulBuilder(builder: (context, change) => AlertDialog(
        title: Text(index == null ? 'Novo perfil' : 'Editar perfil'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, maxLength: 28,
            decoration: const InputDecoration(labelText: 'Nome')),
          TextField(controller: minutes, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Duração (1–1440 minutos)')),
          DropdownButtonFormField<String>(initialValue: mode,
            decoration: const InputDecoration(labelText: 'Alerta'),
            items: const [
              DropdownMenuItem(value: 'sound', child: Text('Som curto')),
              DropdownMenuItem(value: 'vibrate', child: Text('Vibração')),
              DropdownMenuItem(value: 'silent', child: Text('Silencioso')),
            ], onChanged: (v) => change(() => mode = v ?? 'sound')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar')),
          FilledButton(onPressed: () {
            final n = int.tryParse(minutes.text);
            if (name.text.trim().isEmpty || n == null || n < 1 || n > 1440) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Informe um nome e tempo de 1 a 1440 minutos.')));
              return;
            }
            Navigator.pop(context, {'name':name.text.trim(),
              'seconds':n*60, 'mode':mode});
          }, child: const Text('Salvar'))],
      )));
    name.dispose(); minutes.dispose();
    if (result == null || !mounted) return;
    setState(() { if (index == null) { profiles.add(result); } else { profiles[index] = result; }});
    widget.onSave(profiles);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Perfis personalizados')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: profiles.length >= 16 ? null : () => edit(),
      label: const Text('Novo perfil'), icon: const Icon(Icons.add)),
    body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(16,12,16,95),
      children: [
        const Padding(padding: EdgeInsets.only(bottom: 15),
          child: Text('Toque em um perfil para aplicá-lo ao cronômetro.',
            style: TextStyle(color: Color(0xFF596C89)))),
        for (var i=0; i<profiles.length; i++) Card(
          key: ValueKey('${profiles[i]['name']}-$i'),
          child: ListTile(
            leading: const Icon(Icons.bookmark_outline, color: blue),
            title: Text(profiles[i]['name'] as String),
            subtitle: Text('${(profiles[i]['seconds'] as int) ~/ 60} minutos • '
              '${profiles[i]['mode'] == 'sound' ? 'Som' : profiles[i]['mode'] == 'vibrate' ? 'Vibração' : 'Silencioso'}'),
            onTap: () { widget.onSelect(profiles[i]); Navigator.pop(context); },
            trailing: PopupMenuButton<String>(onSelected: (choice) {
              if (choice == 'edit') { edit(i); } else {
                setState(() => profiles.removeAt(i)); widget.onSave(profiles);
              }
            }, itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Editar')),
              PopupMenuItem(value: 'delete', child: Text('Excluir')),
            ]),
          )),
      ])),
  );
}

class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key, required this.history});
  final List<Map<String, dynamic>> history;
  String dayKey(DateTime day) => '${day.year}-${day.month.toString().padLeft(2,'0')}-${day.day.toString().padLeft(2,'0')}';
  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final recent = List.generate(7, (i) => today.subtract(Duration(days: 6-i)));
    final durations = <String,int>{};
    for (final e in history) {
      final key = (e['day'] ?? '').toString();
      durations[key] = (durations[key] ?? 0) + ((e['seconds'] as num?)?.toInt() ?? 0);
    }
    final todaySessions = history.where((e) => e['day'] == dayKey(today)).length;
    final todaySeconds = durations[dayKey(today)] ?? 0;
    final maxMinutes = recent.map((day) => durations[dayKey(day)] ?? 0)
      .fold<int>(60, (a,b) => a > b ? a : b);
    return Scaffold(appBar: AppBar(title: const Text('Minhas estatísticas')),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Sua concentração', style: TextStyle(fontSize: 25,
            fontWeight: FontWeight.bold, color: navy)),
          const SizedBox(height: 5),
          const Text('Somente ciclos concluídos • Dados no dispositivo',
            style: TextStyle(color: Color(0xFF60708D))),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _Metric(value: '$todaySessions', label: 'Ciclos hoje')),
            const SizedBox(width: 12),
            Expanded(child: _Metric(value: '${todaySeconds ~/ 60}', label: 'Minutos hoje')),
          ]),
          const SizedBox(height: 28),
          const Text('Últimos 7 dias', style: TextStyle(fontSize: 21,
            fontWeight: FontWeight.bold, color: navy)),
          const SizedBox(height: 14),
          Container(padding: const EdgeInsets.fromLTRB(12,16,12,8),
            decoration: BoxDecoration(color: const Color(0xFFF0F5FF),
              borderRadius: BorderRadius.circular(18)),
            child: SizedBox(height: 186, child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [for (final day in recent)
                Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text('${(durations[dayKey(day)] ?? 0) ~/ 60}',
                      style: const TextStyle(fontSize: 11, color: navy)),
                    const SizedBox(height: 5),
                    Container(height: 6+125*(durations[dayKey(day)] ?? 0)/maxMinutes,
                      decoration: BoxDecoration(color: blue,
                        borderRadius: BorderRadius.circular(6))),
                    const SizedBox(height: 6),
                    Text('${day.day}/${day.month}',
                      style: const TextStyle(fontSize: 9, color: navy)),
                  ])))],
            )),
          ),
          const SizedBox(height: 28),
          Text('${history.length} ciclos registrados',
            style: const TextStyle(fontWeight: FontWeight.w600, color: navy)),
          const SizedBox(height: 10),
          if (history.isEmpty) const Text('Conclua um cronômetro para ver seu histórico.',
            style: TextStyle(color: Color(0xFF60708D)))
          else for (final e in history.take(20)) ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.check_circle_outline, color: blue),
            title: Text(e['label'] as String),
            subtitle: Text(e['day'] as String),
            trailing: Text('${(e['seconds'] as int) ~/ 60} min')),
        ]),
      ))),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value, label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: const Color(0xFFECF3FF),
      borderRadius: BorderRadius.circular(18)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: const TextStyle(fontSize: 31, fontWeight: FontWeight.bold,
        color: navy)),
      Text(label, style: const TextStyle(color: Color(0xFF60708D))),
    ]),
  );
}
