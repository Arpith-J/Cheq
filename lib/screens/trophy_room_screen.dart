// lib/screens/trophy_room_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../providers/rewards_provider.dart';

class TrophyRoomScreen extends ConsumerWidget {
  const TrophyRoomScreen({super.key});

  static const List<_Badge> _allBadges = [
    _Badge(
      id: nightOwlBadge,
      title: 'Night Owl',
      description: 'Finish a planner task after 10 PM',
      icon: Icons.nightlight_round,
    ),
    _Badge(
      id: scholarBadge,
      title: 'The Scholar',
      description: 'Log deep-focus study sessions',
      icon: Icons.school_rounded,
    ),
    _Badge(
      id: unbreakableBadge,
      title: 'Unbreakable',
      description: 'Keep your daily streak alive',
      icon: Icons.local_fire_department_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(rewardsProvider);
    final cs = Theme.of(context).colorScheme;
    final unlocked = user.unlockedBadges.toSet();

    return Scaffold(
      appBar: AppBar(title: const Text('Trophy Room')),
      backgroundColor: cs.surface,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _StatsHeader(user: user, cs: cs),
          const SizedBox(height: 24),
          Text(
            'Badges',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '${unlocked.length}/${_allBadges.length} collected',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _allBadges.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.92,
            ),
            itemBuilder: (context, i) {
              final badge = _allBadges[i];
              final isUnlocked = unlocked.contains(badge.id);
              return _BadgeCard(badge: badge, isUnlocked: isUnlocked, cs: cs);
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header — coins + streak
// ---------------------------------------------------------------------------

class _StatsHeader extends StatelessWidget {
  const _StatsHeader({required this.user, required this.cs});

  final UserModel user;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _HeaderCard(
            icon: Icons.monetization_on_rounded,
            iconColor: const Color(0xFFFFD54F),
            label: 'Coins',
            value: '${user.coins}',
            cs: cs,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _HeaderCard(
            icon: Icons.local_fire_department_rounded,
            iconColor: cs.error,
            label: 'Day Streak',
            value: '${user.streakCount}',
            cs: cs,
          ),
        ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.cs,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: iconColor),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Badge card
// ---------------------------------------------------------------------------

class _BadgeCard extends StatelessWidget {
  const _BadgeCard({
    required this.badge,
    required this.isUnlocked,
    required this.cs,
  });

  final _Badge badge;
  final bool isUnlocked;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isUnlocked
            ? cs.primaryContainer.withValues(alpha: 0.35)
            : cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUnlocked
              ? cs.primary.withValues(alpha: 0.4)
              : cs.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isUnlocked
                  ? cs.primaryContainer
                  : cs.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: isUnlocked
                ? Icon(badge.icon, size: 30, color: cs.primary)
                : ColorFiltered(
                    colorFilter: const ColorFilter.matrix(<double>[
                      0.2126, 0.7152, 0.0722, 0, 0, //
                      0.2126, 0.7152, 0.0722, 0, 0, //
                      0.2126, 0.7152, 0.0722, 0, 0, //
                      0,      0,      0,      1, 0, //
                    ]),
                    child: Icon(
                      badge.icon,
                      size: 30,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          Text(
            badge.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isUnlocked ? cs.onSurface : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            badge.description,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    if (!isUnlocked) {
      return Opacity(opacity: 0.3, child: content);
    }

    return content;
  }
}

// ---------------------------------------------------------------------------
// Badge metadata
// ---------------------------------------------------------------------------

class _Badge {
  final String id;
  final String title;
  final String description;
  final IconData icon;

  const _Badge({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
  });
}
