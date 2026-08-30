// lib/screens/tools_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';

/// Singleton used to trigger the audible completion chimes for the timers.
final _ringtonePlayer = FlutterRingtonePlayer();

/// Hub for the standalone time-management utilities: Pomodoro, Countdown
/// Timer, and Stopwatch. Each tab owns its own [StatefulWidget] so every
/// `Timer` is cancelled in `dispose()` — navigating away from the screen can
/// never leak an active ticker or leave a stale Pomodoro alarm behind.
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Productivity Tools'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.timer_outlined), text: 'Pomodoro'),
              Tab(icon: Icon(Icons.hourglass_top_rounded), text: 'Timer'),
              Tab(icon: Icon(Icons.av_timer_rounded), text: 'Stopwatch'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _PomodoroTab(),
            _CountdownTimerTab(),
            _StopwatchTab(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared duration formatting helpers
// ---------------------------------------------------------------------------

String _two(int n) => n.toString().padLeft(2, '0');

/// Fixed-width `HH:MM:SS` clock (used by the Timer tab).
String _formatHms(Duration d) =>
    '${_two(d.inHours)}:${_two(d.inMinutes % 60)}:${_two(d.inSeconds % 60)}';

/// `HH:MM:SS.cc` stopwatch format (centiseconds as the visible fraction).
String _formatHmsCentis(Duration d) =>
    '${_formatHms(d)}.${_two((d.inMilliseconds % 1000) ~/ 10)}';

/// `M:SS`, promoting to `H:MM:SS` only past one hour (used inside the
/// Pomodoro ring where blocks are short).
String _formatSmart(Duration d) {
  final h = d.inHours;
  if (h > 0) return _formatHms(d);
  return '${_two(d.inMinutes % 60)}:${_two(d.inSeconds % 60)}';
}

// ---------------------------------------------------------------------------
// Pomodoro tab
// ---------------------------------------------------------------------------

enum _PomodoroPhase { focus, shortBreak, longBreak }

class _PomodoroBlock {
  const _PomodoroBlock(this.phase, this.duration);

  final _PomodoroPhase phase;
  final Duration duration;
}

/// Splits a total session length into alternating Focus / Rest blocks using
/// the classic cadence: up to 25 minutes of focus, then a 5-minute break —
/// promoted to 15 minutes after every fourth focus block. A trailing partial
/// focus block absorbs whatever time remains, and no break is appended after
/// the final focus block (the session simply ends).
List<_PomodoroBlock> _buildPomodoroBlocks(Duration total) {
  const focusLength = Duration(minutes: 25);
  const shortBreak = Duration(minutes: 5);
  const longBreak = Duration(minutes: 15);

  final blocks = <_PomodoroBlock>[];
  var remaining = total;
  var focusCount = 0;

  while (remaining > Duration.zero) {
    final focus = remaining < focusLength ? remaining : focusLength;
    blocks.add(_PomodoroBlock(_PomodoroPhase.focus, focus));
    remaining -= focus;
    focusCount++;

    if (remaining > Duration.zero) {
      blocks.add(_PomodoroBlock(
        focusCount % 4 == 0 ? _PomodoroPhase.longBreak : _PomodoroPhase.shortBreak,
        focusCount % 4 == 0 ? longBreak : shortBreak,
      ));
    }
  }
  return blocks;
}

Color _phaseColor(ColorScheme cs, _PomodoroPhase phase) => switch (phase) {
      _PomodoroPhase.focus => cs.primary,
      _PomodoroPhase.shortBreak => cs.tertiary,
      _PomodoroPhase.longBreak => cs.secondary,
    };

String _phaseLabel(_PomodoroPhase phase) => switch (phase) {
      _PomodoroPhase.focus => 'Focus',
      _PomodoroPhase.shortBreak => 'Short Break',
      _PomodoroPhase.longBreak => 'Long Break',
    };

class _PomodoroTab extends StatefulWidget {
  const _PomodoroTab();

  @override
  State<_PomodoroTab> createState() => _PomodoroTabState();
}

class _PomodoroTabState extends State<_PomodoroTab> {
  static const _notificationIdBase = 910000;

  // ---------------------------------------------------------------------------
  // SharedPreferences persistence keys for the Pomodoro session so its timer
  // survives an app restart (active or paused).
  // ---------------------------------------------------------------------------
  static const _prefEndTime = 'pomodoro_end_time'; // ISO-8601, active session
  static const _prefMode = 'pomodoro_timer_mode'; // focus / shortBreak / longBreak
  static const _prefTotal = 'pomodoro_total_session_time'; // seconds, active+paused
  static const _prefPausedRemaining =
      'pomodoro_paused_remaining'; // seconds remaining, paused state

  final _minutesCtrl = TextEditingController(text: '50');
  final _minutesFocus = FocusNode();

  Timer? _tick;
  DateTime? _lastTickAt;
  Duration _elapsed = Duration.zero;
  List<_PomodoroBlock> _blocks = const [];
  bool _running = false;
  bool _finished = false;
  bool _hydrated = false;

  /// Index of the last block whose completion already triggered a chime, so a
  /// focus/rest transition rings exactly once (and never on pause/reset).
  int _lastChimedBlockIndex = -1;

  /// Ids of the boundary notifications scheduled for the live session, so
  /// they can be deterministically cancelled on pause/reset/dispose.
  final Set<int> _scheduledNotificationIds = {};

  Duration get _sessionTotal => _blocks.fold(
        Duration.zero,
        (sum, block) => sum + block.duration,
      );

  _PomodoroPhase get _currentPhase =>
      _blocks.isEmpty ? _PomodoroPhase.focus : _blocks[_currentBlockIndex].phase;

  @override
  void initState() {
    super.initState();
    _restoreSavedSession();
  }

  /// Loads any saved active/paused Pomodoro session from SharedPreferences and
  /// reinstates it so the timer state survives an app restart.
  Future<void> _restoreSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final totalSeconds = prefs.getInt(_prefTotal);
    if (totalSeconds == null || totalSeconds <= 0) {
      setState(() => _hydrated = true);
      return;
    }

    // Rebuild the identical block plan from the saved total session time.
    final total = Duration(seconds: totalSeconds);
    setState(() {
      _blocks = _buildPomodoroBlocks(total);
      _minutesCtrl.text = '${total.inMinutes}';
    });

    // --- Active session: endTime is still set, resume the countdown. ---
    final endTimeIso = prefs.getString(_prefEndTime);
    if (endTimeIso != null) {
      final endTime = DateTime.tryParse(endTimeIso);
      if (endTime != null) {
        final remaining = endTime.difference(DateTime.now());
        // Clamp: a session that already overran keeps the full dev offset so a
        // live transition fires before reload rather than silently clobbering.
        final totalRemaining =
            remaining.isNegative ? Duration.zero : remaining;
        setState(() {
          _elapsed = total - totalRemaining;
          _hydrated = true;
        });
        if (_elapsed >= _sessionTotal) {
          _completeSession();
        } else {
          // Resume ticking from the surviving elapsed position.
          _lastChimedBlockIndex = _currentBlockIndex;
          _running = true;
          _lastTickAt = DateTime.now();
          _tick =
              Timer.periodic(const Duration(milliseconds: 250), (_) => _onTick());
          _syncBoundaryNotifications();
        }
        return;
      }
    }

    // --- Paused session: endTime consumed, resume in a waiting state. ---
    final pausedSeconds = prefs.getInt(_prefPausedRemaining);
    if (pausedSeconds != null && pausedSeconds > 0) {
      final remaining = Duration(seconds: pausedSeconds);
      setState(() {
        _elapsed = total - remaining;
        _hydrated = true;
      });
      _lastChimedBlockIndex = _currentBlockIndex;
      return;
    }

    setState(() => _hydrated = true);
  }

  /// Writes the currently-running session so it can be resumed after a restart.
  Future<void> _persistActive() async {
    final prefs = await SharedPreferences.getInstance();
    final totalSeconds = _sessionTotal.inSeconds;
    final endTime = DateTime.now().add(_sessionTotal - _elapsed);
    final prefsFuture = prefs
        .setString(_prefEndTime, endTime.toIso8601String())
        .then((_) => prefs.setString(_prefMode, _currentPhase.name))
        .then((_) => prefs.setInt(_prefTotal, totalSeconds))
        // A fresh active write supersedes any stale paused marker.
        .then((_) => prefs.remove(_prefPausedRemaining));
    await prefsFuture;
  }

  /// Stores only the paused position (no `endTime`), so on the next launch the
  /// timer holds in place instead of counting down while the app is closed.
  Future<void> _persistPaused() async {
    final prefs = await SharedPreferences.getInstance();
    final remaining = _sessionTotal - _elapsed;
    final prefsFuture = prefs
        .remove(_prefEndTime)
        .then((_) => prefs.setInt(_prefPausedRemaining, remaining.inSeconds))
        .then((_) => prefs.setInt(_prefTotal, _sessionTotal.inSeconds))
        .then((_) => prefs.setString(_prefMode, _currentPhase.name));
    await prefsFuture;
  }

  /// Clears all saved Pomodoro session markers.
  Future<void> _clearPersistence() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_prefEndTime),
      prefs.remove(_prefMode),
      prefs.remove(_prefTotal),
      prefs.remove(_prefPausedRemaining),
    ]);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _cancelBoundaryNotifications();
    _minutesCtrl.dispose();
    _minutesFocus.dispose();
    super.dispose();
  }

  int get _currentBlockIndex {
    var cumulative = Duration.zero;
    for (var i = 0; i < _blocks.length; i++) {
      cumulative += _blocks[i].duration;
      if (_elapsed < cumulative) return i;
    }
    return _blocks.isEmpty ? 0 : _blocks.length - 1;
  }

  double get _blockProgress {
    if (_blocks.isEmpty || _finished) return _finished ? 1 : 0;
    var before = Duration.zero;
    for (var i = 0; i < _currentBlockIndex; i++) {
      before += _blocks[i].duration;
    }
    final current = _blocks[_currentBlockIndex];
    final intoBlock = (_elapsed - before).inMilliseconds.clamp(0, current.duration.inMilliseconds);
    return intoBlock / current.duration.inMilliseconds;
  }

  void _onTick() {
    final now = DateTime.now();
    setState(() {
      _elapsed += now.difference(_lastTickAt ?? now);
      _lastTickAt = now;
    });
    if (_elapsed >= _sessionTotal) {
      _completeSession();
      return;
    }
    // A focus/rest block just hit zero — ring the transition chime once.
    final index = _currentBlockIndex;
    if (index != _lastChimedBlockIndex) {
      _ringtonePlayer.playNotification();
      _lastChimedBlockIndex = index;
    }
  }

  Future<void> _start() async {
    if (_running || _finished) return;

    // First start of a fresh session: parse the input and split it.
    if (_blocks.isEmpty) {
      final minutes = int.tryParse(_minutesCtrl.text.trim()) ?? 0;
      if (minutes <= 0) {
        _minutesFocus.requestFocus();
        return;
      }
      setState(() {
        _blocks = _buildPomodoroBlocks(Duration(minutes: minutes));
        _elapsed = Duration.zero;
        _lastChimedBlockIndex = -1;
      });
    } else {
      setState(() {});
    }

    _running = true;
    _lastTickAt = DateTime.now();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _onTick());
    _syncBoundaryNotifications();
    // Remember the absolute end time so a restart can resume the countdown.
    await _persistActive();
  }

  void _pause() {
    if (!_running) return;
    final now = DateTime.now();
    setState(() {
      _elapsed += now.difference(_lastTickAt ?? now);
      _lastTickAt = null;
      _running = false;
    });
    _tick?.cancel();
    _tick = null;
    _cancelBoundaryNotifications();
    // Swap the live `endTime` for a fixed remaining-seconds marker so the
    // timer parks (instead of counting down) across an app restart.
    unawaited(_persistPaused());
  }

  void _reset() {
    _tick?.cancel();
    _tick = null;
    _cancelBoundaryNotifications();
    unawaited(_clearPersistence());
    setState(() {
      _running = false;
      _finished = false;
      _elapsed = Duration.zero;
      _blocks = const [];
      _lastTickAt = null;
      _lastChimedBlockIndex = -1;
    });
  }

  void _completeSession() {
    _tick?.cancel();
    _tick = null;
    _cancelBoundaryNotifications();
    unawaited(_clearPersistence());
    // Ring a final chime when the last block naturally reaches zero.
    _ringtonePlayer.playNotification();
    setState(() {
      _running = false;
      _finished = true;
      _elapsed = _sessionTotal;
    });
  }

  /// (Re)schedules one local notification per upcoming phase boundary:
  /// finishing a focus block announces the rest period that follows, finishing
  /// a break announces the next focus block, and the last boundary celebrates
  /// the completed session. Called on every start/resume so pause + resume
  /// re-anchors the alarms to the remaining offsets.
  Future<void> _syncBoundaryNotifications() async {
    await _cancelBoundaryNotifications();

    var offset = Duration.zero;
    for (var i = 0; i < _blocks.length; i++) {
      final block = _blocks[i];
      offset += block.duration;

      final untilBoundary = offset - _elapsed;
      if (untilBoundary <= Duration.zero) continue;

      String title;
      String body;
      if (i == _blocks.length - 1) {
        title = 'Pomodoro Complete';
        body = 'You finished the full session — great work!';
      } else if (block.phase == _PomodoroPhase.focus) {
        final next = _blocks[i + 1];
        title = 'Focus Block ${(i ~/ 2) + 1} Complete';
        body =
            'Time for a ${next.duration.inMinutes} minute ${_phaseLabel(next.phase).toLowerCase()}.';
      } else {
        title = 'Break Over';
        body = 'Your next focus block starts now.';
      }

      final id = _notificationIdBase + i;
      try {
        await NotificationService.instance.scheduleNotification(
          id: id,
          title: title,
          body: body,
          scheduledTime: DateTime.now().add(untilBoundary),
          payload: 'pomodoro_boundary',
          // No actions: a Pomodoro alarm must not offer 'Mark as complete'.
          actions: const <AndroidNotificationAction>[],
        );
        _scheduledNotificationIds.add(id);
      } catch (e) {
        debugPrint('Failed to schedule Pomodoro boundary notification: $e');
      }
    }
  }

  Future<void> _cancelBoundaryNotifications() async {
    for (final id in _scheduledNotificationIds) {
      try {
        await NotificationService.instance.cancelNotification(id);
      } catch (_) {}
    }
    _scheduledNotificationIds.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── SESSION SETUP ──
            Text(
              'TOTAL SESSION TIME',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minutesCtrl,
                    focusNode: _minutesFocus,
                    enabled: _blocks.isEmpty,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Minutes',
                      suffixText: 'min',
                      filled: true,
                      fillColor: cs.surfaceContainerHigh.withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (_blocks.isEmpty) ...[
                  TextButton.icon(
                    onPressed: () {
                      final minutes = int.tryParse(_minutesCtrl.text.trim()) ?? 0;
                      if (minutes <= 0) {
                        _minutesFocus.requestFocus();
                        return;
                      }
                      setState(() {
                        _blocks = _buildPomodoroBlocks(Duration(minutes: minutes));
                        _elapsed = Duration.zero;
                      });
                    },
                    icon: const Icon(Icons.schedule_rounded, size: 18),
                    label: const Text('Preview'),
                  ),
                ] else ...[
                  Text(
                    '${_blocks.where((b) => b.phase == _PomodoroPhase.focus).length} focus · '
                    '${_formatSmart(_sessionTotal)} total',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),

            // ── BLOCK PLAN PREVIEW ──
            if (_blocks.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < _blocks.length; i++)
                    Tooltip(
                      message: _phaseLabel(_blocks[i].phase),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _phaseColor(cs, _blocks[i].phase)
                              .withValues(alpha: _elapsed >= _blockStart(i + 1)
                                  ? 0.18
                                  : (_elapsed >= _blockStart(i) ? 0.45 : 0.12)),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${_phaseLabel(_blocks[i].phase).characters.first}'
                          '${_blocks[i].duration.inMinutes}m',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],

            const SizedBox(height: 28),

            // ── LIVE COUNTDOWN RING ──
            Center(
              child: SizedBox(
                width: 240,
                height: 240,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 240,
                      height: 240,
                      child: CircularProgressIndicator(
                        value: _blocks.isEmpty ? null : _blockProgress,
                        strokeWidth: 12,
                        strokeCap: StrokeCap.round,
                        backgroundColor:
                            cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        color: _blocks.isEmpty
                            ? cs.primary
                            : _phaseColor(cs, _blocks[_currentBlockIndex].phase),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: _blocks.isEmpty
                                ? cs.surfaceContainerHigh
                                : _phaseColor(cs, _blocks[_currentBlockIndex].phase)
                                    .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            !_hydrated || _blocks.isEmpty
                                ? 'Ready'
                                : _phaseLabel(_blocks[_currentBlockIndex].phase),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: !_hydrated || _blocks.isEmpty
                                  ? cs.onSurfaceVariant
                                  : _phaseColor(cs, _blocks[_currentBlockIndex].phase),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          !_hydrated || _blocks.isEmpty
                              ? '--:--'
                              : _formatSmart(_blockRemaining(_currentBlockIndex)),
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: cs.onSurface,
                          ),
                        ),
                        if (_blocks.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Session left ${_formatSmart(_sessionTotal - _elapsed)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),
            if (_finished)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Session complete! Take a real rest.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // ── CONTROLS ──
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _finished ? null : (_running ? _pause : _start),
                  icon: Icon(
                    _running
                        ? Icons.pause_rounded
                        : (_elapsed > Duration.zero
                            ? Icons.play_arrow_rounded
                            : Icons.play_circle_outline_rounded),
                  ),
                  label: Text(_running
                      ? 'Pause'
                      : (_elapsed > Duration.zero ? 'Resume' : 'Start Session')),
                ),
                const SizedBox(width: 12),
                IconButton.outlined(
                  tooltip: 'Reset',
                  onPressed: _blocks.isEmpty && !_finished ? null : _reset,
                  icon: const Icon(Icons.restart_alt_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Duration _blockStart(int index) {
    var start = Duration.zero;
    for (var i = 0; i < index && i < _blocks.length; i++) {
      start += _blocks[i].duration;
    }
    return start;
  }

  Duration _blockRemaining(int index) {
    if (_blocks.isEmpty) return Duration.zero;
    final start = _blockStart(index);
    final end = start + _blocks[index].duration;
    if (_elapsed <= start) return _blocks[index].duration;
    if (_elapsed >= end) return Duration.zero;
    return end - _elapsed;
  }
}

// ---------------------------------------------------------------------------
// Timer tab
// ---------------------------------------------------------------------------

class _CountdownTimerTab extends StatefulWidget {
  const _CountdownTimerTab();

  @override
  State<_CountdownTimerTab> createState() => _CountdownTimerTabState();
}

class _CountdownTimerTabState extends State<_CountdownTimerTab> {
  static const _presets = <String, Duration>{
    '15m': Duration(minutes: 15),
    '30m': Duration(minutes: 30),
    '1hr': Duration(hours: 1),
  };

  Timer? _tick;
  Duration _selected = const Duration(minutes: 15);
  Duration _remaining = const Duration(minutes: 15);
  DateTime? _endAt;
  bool _running = false;
  bool _finished = false;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _selectPreset(Duration duration) {
    if (_running) return;
    _tick?.cancel();
    _tick = null;
    setState(() {
      _selected = duration;
      _remaining = duration;
      _endAt = null;
      _finished = false;
    });
  }

  Future<void> _pickCustom() async {
    if (_running) return;
    final picked = await showDialog<Duration>(
      context: context,
      builder: (ctx) => _DurationPickerDialog(initial: _selected),
    );
    if (picked == null || picked <= Duration.zero) return;
    _selectPreset(picked);
  }

  void _start() {
    if (_running || _remaining <= Duration.zero) return;
    setState(() {
      _endAt = DateTime.now().add(_remaining);
      _running = true;
      _finished = false;
    });
    // Deadline-based ticking: each beat recomputes what is actually left, so
    // background throttling can never let the countdown drift.
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final left = _endAt?.difference(DateTime.now()) ?? Duration.zero;
      if (left <= Duration.zero) {
        _finish();
      } else {
        setState(() => _remaining = left);
      }
    });
  }

  void _pause() {
    if (!_running) return;
    setState(() {
      _remaining = _endAt?.difference(DateTime.now()) ?? _remaining;
      _running = false;
    });
    _tick?.cancel();
    _tick = null;
  }

  void _reset() {
    _tick?.cancel();
    _tick = null;
    setState(() {
      _running = false;
      _finished = false;
      _remaining = _selected;
      _endAt = null;
    });
  }

  void _finish() {
    _tick?.cancel();
    _tick = null;
    // Only reached when the countdown naturally hits zero — never on pause or
    // reset. Use a brief (non-looping) notification ding, never an alarm loop.
    _ringtonePlayer.playNotification();
    setState(() {
      _running = false;
      _finished = true;
      _remaining = Duration.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress =
        _selected > Duration.zero ? 1 - (_remaining.inMilliseconds / _selected.inMilliseconds) : 0.0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          children: [
            // ── PRESETS ──
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final entry in _presets.entries)
                  ChoiceChip(
                    label: Text(entry.key),
                    selected: !_running &&
                        _selected == entry.value &&
                        !_isCustomSelection,
                    onSelected: (_) => _selectPreset(entry.value),
                  ),
                ChoiceChip(
                  avatar: Icon(Icons.tune_rounded,
                      size: 16,
                      color: _isCustomSelection ? cs.onSecondaryContainer : cs.onSurfaceVariant),
                  label: const Text('Custom'),
                  selected: _isCustomSelection,
                  onSelected: (_) => _pickCustom(),
                ),
              ],
            ),

            const Spacer(),

            // ── LARGE HH:MM:SS COUNTDOWN ──
            Text(
              _formatHms(_remaining),
              style: TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: _finished ? cs.primary : cs.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor:
                      cs.surfaceContainerHighest.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _finished
                  ? "Time's up!"
                  : _running
                      ? 'Ends at ${TimeOfDay.fromDateTime(_endAt!).format(context)}'
                      : 'Ready · ${_selected.inHours > 0 ? '${_selected.inHours} hr ' : ''}${_selected.inMinutes % 60} min${_selected.inSeconds % 60 > 0 ? ' ${_selected.inSeconds % 60} sec' : ''}',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),

            const Spacer(),

            // ── CONTROLS ──
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed:
                      _finished ? null : (_running ? _pause : _start),
                  icon: Icon(_running
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded),
                  label: Text(_running
                      ? 'Pause'
                      : (_remaining < _selected ? 'Resume' : 'Start')),
                ),
                const SizedBox(width: 12),
                IconButton.outlined(
                  tooltip: 'Reset',
                  onPressed: (_remaining == _selected && !_finished && !_running)
                      ? null
                      : _reset,
                  icon: const Icon(Icons.restart_alt_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool get _isCustomSelection => !_presets.values.contains(_selected);
}

/// Hours / Minutes / Seconds picker used by the Timer tab's Custom chip.
class _DurationPickerDialog extends StatefulWidget {
  const _DurationPickerDialog({required this.initial});

  final Duration initial;

  @override
  State<_DurationPickerDialog> createState() => _DurationPickerDialogState();
}

class _DurationPickerDialogState extends State<_DurationPickerDialog> {
  late int _hours = widget.initial.inHours.clamp(0, 23);
  late int _minutes = (widget.initial.inMinutes % 60).clamp(0, 59);
  late int _seconds = (widget.initial.inSeconds % 60).clamp(0, 59);

  bool get _isZero => _hours == 0 && _minutes == 0 && _seconds == 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom Timer'),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _pickerColumn('Hours', 23, _hours, (v) => setState(() => _hours = v)),
          _pickerColumn(
              'Minutes', 59, _minutes, (v) => setState(() => _minutes = v)),
          _pickerColumn(
              'Seconds', 59, _seconds, (v) => setState(() => _seconds = v)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isZero
              ? null
              : () => Navigator.pop(
                  context,
                  Duration(hours: _hours, minutes: _minutes, seconds: _seconds)),
          child: const Text('Set'),
        ),
      ],
    );
  }

  Widget _pickerColumn(
    String label,
    int max,
    int value,
    ValueChanged<int> onChanged,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: cs.onSurfaceVariant,
          ),
        ),
        SizedBox(
          height: 160,
          width: 72,
          child: ListWheelScrollView.useDelegate(
            itemExtent: 36,
            diameterRatio: 1.4,
            perspective: 0.004,
            physics: const FixedExtentScrollPhysics(),
            controller: FixedExtentScrollController(initialItem: value),
            onSelectedItemChanged: onChanged,
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: max + 1,
              builder: (ctx, index) => Center(
                child: Text(
                  _two(index),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight:
                        index == value ? FontWeight.w700 : FontWeight.w400,
                    color:
                        index == value ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Stopwatch tab
// ---------------------------------------------------------------------------

class _StopwatchTab extends StatefulWidget {
  const _StopwatchTab();

  @override
  State<_StopwatchTab> createState() => _StopwatchTabState();
}

class _StopwatchTabState extends State<_StopwatchTab> {
  Timer? _tick;
  DateTime? _lastTickAt;
  Duration _elapsed = Duration.zero;
  bool _running = false;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _start() {
    if (_running) return;
    setState(() => _running = true);
    _lastTickAt = DateTime.now();
    // Real-time updates: elapsed grows by actual wall-clock deltas instead of
    // fixed decrements, so throttled frames can never lose time.
    _tick = Timer.periodic(const Duration(milliseconds: 30), (_) {
      final now = DateTime.now();
      setState(() {
        _elapsed += now.difference(_lastTickAt ?? now);
        _lastTickAt = now;
      });
    });
  }

  void _pause() {
    if (!_running) return;
    final now = DateTime.now();
    setState(() {
      _elapsed += now.difference(_lastTickAt ?? now);
      _lastTickAt = null;
      _running = false;
    });
    _tick?.cancel();
    _tick = null;
  }

  void _reset() {
    _tick?.cancel();
    _tick = null;
    setState(() {
      _elapsed = Duration.zero;
      _running = false;
      _lastTickAt = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          children: [
            const Spacer(),
            Text(
              _formatHmsCentis(_elapsed),
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _running ? 'Running…' : 'Stopped',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _running ? _pause : _start,
                  icon: Icon(
                      _running ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  label: Text(_running ? 'Pause' : (_elapsed > Duration.zero ? 'Resume' : 'Start')),
                ),
                const SizedBox(width: 12),
                IconButton.outlined(
                  tooltip: 'Reset',
                  onPressed: _elapsed == Duration.zero && !_running ? null : _reset,
                  icon: const Icon(Icons.restart_alt_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
