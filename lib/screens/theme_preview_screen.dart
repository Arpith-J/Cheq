// lib/screens/theme_preview_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import '../providers/rewards_provider.dart';
import '../theme/app_themes.dart';

/// Shows a live mock-up of the app dressed in the selected theme, a natural
/// color-only description, and a single "Buy & Equip" / "Equip" action.
class ThemePreviewScreen extends ConsumerStatefulWidget {
  const ThemePreviewScreen({super.key, required this.entry});

  final ThemeCatalogEntry entry;

  @override
  ConsumerState<ThemePreviewScreen> createState() => _ThemePreviewScreenState();
}

class _ThemePreviewScreenState extends ConsumerState<ThemePreviewScreen> {
  bool _isBusy = false;

  ThemeData get _previewTheme {
    final entry = widget.entry;
    final brightness = entry.previewBackground.computeLuminance() > 0.5
        ? Brightness.light
        : Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: entry.previewAccent,
        brightness: brightness,
      ),
      scaffoldBackgroundColor: entry.previewBackground,
    );
  }

  Future<void> _handlePrimaryAction(
    UserModel user,
    bool isUnlocked,
  ) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    final notifier = ref.read(rewardsProvider.notifier);
    final entry = widget.entry;

    var proceed = isUnlocked;
    if (!proceed) {
      proceed = await notifier.purchaseTheme(entry.id, entry.cost);
      if (!proceed) {
        if (mounted) {
          setState(() => _isBusy = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Not enough coins for ${entry.name}.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }

    final equipped = await notifier.equipTheme(entry.id);

    if (!mounted) return;
    setState(() => _isBusy = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(equipped
            ? '${entry.name} is now your active theme!'
            : 'Could not equip ${entry.name}.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final userAsync = ref.watch(userStreamProvider);
    final user = userAsync.value ??
        const UserModel(uid: '', displayName: '', email: '');

    final isActive = user.activeTheme == entry.id;
    final isUnlocked =
        entry.id == themeIdDefault || user.unlockedThemes.contains(entry.id);
    final canAfford = user.coins >= entry.cost;
    final isFree = entry.cost <= 0;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(
          entry.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  // ── Themed mock-up ──────────────────────────────────────
                  Theme(
                    data: _previewTheme,
                    child: _AppMockup(accent: entry.previewAccent),
                  ),
                  const SizedBox(height: 20),
                  // ── Color-only description ──────────────────────────────
                  Card(
                    elevation: 0,
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.palette_outlined,
                            size: 20,
                            color: entry.previewAccent,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Look & Feel',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  entry.colorDescription,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.4,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Primary action ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: _buildAction(user, isActive, isUnlocked, canAfford,
                    isFree),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(
    UserModel user,
    bool isActive,
    bool isUnlocked,
    bool canAfford,
    bool isFree,
  ) {
    final entry = widget.entry;

    if (isActive) {
      return FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check_rounded, size: 18),
        label: const Text('Equipped'),
      );
    }

    if (isUnlocked) {
      return FilledButton.icon(
        onPressed: _isBusy ? null : () => _handlePrimaryAction(user, true),
        icon: const Icon(Icons.palette_outlined, size: 18),
        label: Text(_isBusy ? 'Equipping…' : 'Equip'),
      );
    }

    final enabled = canAfford && !_isBusy && !isFree;
    return FilledButton.icon(
      onPressed: enabled ? () => _handlePrimaryAction(user, false) : null,
      icon: Icon(
        canAfford ? Icons.shopping_bag_outlined : Icons.lock_outline,
        size: 18,
      ),
      label: Text(
        _isBusy
            ? 'Buying…'
            : isFree
                ? 'Equip'
                : 'Buy & Equip for ${entry.cost} Coins',
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Static app mock-up rendered inside the preview theme
// ---------------------------------------------------------------------------

class _AppMockup extends StatelessWidget {
  const _AppMockup({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 430,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Mock app bar ────────────────────────────────────────────────
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: cs.primaryContainer,
                  child: Icon(Icons.person_rounded, size: 16, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Text(
                  'Planner',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                Text('✨', style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 4),
                Text(
                  '1,250',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          // ── Mock task rows ──────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: const [
                _MockTaskRow(
                  title: 'Morning deep work session',
                  time: '9:00 AM',
                  category: 'FOCUS',
                  done: true,
                ),
                SizedBox(height: 8),
                _MockTaskRow(
                  title: 'Review project roadmap',
                  time: '11:30 AM',
                  category: 'CREATIVITY',
                  done: false,
                ),
                SizedBox(height: 8),
                _MockTaskRow(
                  title: 'Call with the design team',
                  time: '2:00 PM',
                  done: false,
                ),
                SizedBox(height: 8),
                _MockTaskRow(
                  title: 'Evening wrap-up',
                  time: '6:00 PM',
                  done: false,
                ),
              ],
            ),
          ),
          // ── Mock bottom nav ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Icon(Icons.checklist_rounded, size: 20, color: cs.primary),
                Icon(Icons.calendar_today_rounded,
                    size: 20, color: cs.onSurfaceVariant),
                Icon(Icons.emoji_events_outlined,
                    size: 20, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MockTaskRow extends StatelessWidget {
  const _MockTaskRow({
    required this.title,
    required this.time,
    this.category,
    this.done = false,
  });

  final String title;
  final String time;
  final String? category;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text(
            time,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: done ? cs.onSurface.withValues(alpha: 0.3) : cs.primary,
            ),
          ),
          const SizedBox(width: 10),
          if (category != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                category!,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: cs.onPrimaryContainer,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: done
                    ? cs.onSurface.withValues(alpha: 0.35)
                    : cs.onSurface,
                decoration: done ? TextDecoration.lineThrough : null,
                decorationColor: cs.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
          Icon(
            done
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 18,
            color: done ? cs.primary : cs.outlineVariant,
          ),
        ],
      ),
    );
  }
}
