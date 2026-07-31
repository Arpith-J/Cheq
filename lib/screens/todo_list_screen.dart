// lib/screens/todo_list_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../providers/todo_collection_provider.dart';

// ---------------------------------------------------------------------------
// TodoListScreen with Custom 4-Tab Segregation Header
// ---------------------------------------------------------------------------

class TodoListScreen extends ConsumerWidget {
  const TodoListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionsAsync = ref.watch(todoCollectionsProvider);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        appBar: const PreferredSize(
          preferredSize: Size.fromHeight(48),
          child: TabBar(
            isScrollable: false,
            tabAlignment: TabAlignment.fill,
            indicatorSize: TabBarIndicatorSize.tab,
            labelStyle: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
            unselectedLabelStyle: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
            tabs: [
              Tab(text: 'All'),
              Tab(text: 'Tasks'),
              Tab(text: 'Lists'),
              Tab(text: 'Done'),
            ],
          ),
        ),
        body: collectionsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error:   (e, _) => Center(child: Text('Error: $e')),
          data: (allCollections) {
            final now = DateTime.now();
            //final today = DateTime(now.year, now.month, now.day);
            final threeDaysAgo = now.subtract(const Duration(days: 3));

            // Filtering Segregation Rules
            final pendingTasks = allCollections.where((c) => !c.isArchived && c.isSingleTask).toList();
            final pendingLists = allCollections.where((c) => !c.isArchived && !c.isSingleTask).toList();
            
            // Filters items archived/completed within the past 3 consecutive days
            final completedItems = allCollections.where((c) {
              if (!c.isArchived) return false;
              if (c.archivedAt == null) return false;
              return c.archivedAt!.isAfter(threeDaysAgo) || c.archivedAt!.isAtSameMomentAs(threeDaysAgo);
            }).toList();
            return TabBarView(
              children: [
                _buildAllTab(context, ref, pendingTasks, pendingLists),
                _buildTasksTab(pendingTasks),
                _buildListsTab(pendingLists),
                _buildCompletedTab(completedItems),
              ],
            );
          },
        ),
        floatingActionButton: const _ExpandingSpeedDialFab(),
      ),
    );
  }

  // ── Tab Layout Render Engines ─────────────────────────────────────────────

  Widget _buildAllTab(BuildContext context, WidgetRef ref, List<TodoCollection> tasks, List<TodoCollection> lists) {
    if (tasks.isEmpty && lists.isEmpty) {
      return _EmptyState(onAddList: () => _openAddEditSheet(context), onAddTask: () => _openAddTaskDialog(context, ref));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        if (tasks.isNotEmpty) ...[
          _SectionHeader(title: 'Tasks', count: tasks.length),
          const SizedBox(height: 8),
          ...tasks.map((task) => _SingleTaskLineItem(task: task)),
          const SizedBox(height: 24),
        ],
        if (lists.isNotEmpty) ...[
          _SectionHeader(title: 'Lists', count: lists.length),
          const SizedBox(height: 10),
          MasonryGridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount:  2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            itemCount: lists.length,
            itemBuilder: (ctx, i) => _CollectionCard(collection: lists[i]),
          ),
        ],
      ],
    );
  }

  Widget _buildTasksTab(List<TodoCollection> tasks) {
    if (tasks.isEmpty) return const _TabEmptyState(message: 'No pending quick tasks');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: tasks.map((task) => _SingleTaskLineItem(task: task)).toList(),
    );
  }

  Widget _buildListsTab(List<TodoCollection> lists) {
    if (lists.isEmpty) return const _TabEmptyState(message: 'No pending checklists');
    return MasonryGridView.count(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 100),
      crossAxisCount:  2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      itemCount: lists.length,
      itemBuilder: (ctx, i) => _CollectionCard(collection: lists[i]),
    );
  }

  Widget _buildCompletedTab(List<TodoCollection> completed) {
    if (completed.isEmpty) return const _TabEmptyState(message: 'No completions in the past 3 days');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: completed.map((item) {
        if (item.isSingleTask) {
          return _SingleTaskLineItem(task: item);
        } else {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CollectionCard(collection: item),
          );
        }
      }).toList(),
    );
  }

  // ── Action Sheet Sheet Routing Triggers ───────────────────────────────────

  static void _openAddEditSheet(BuildContext context, {TodoCollection? existingCollection}) {
    showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      useSafeArea:        true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddCollectionSheet(existingCollection: existingCollection),
    );
  }

  static void _openAddTaskDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Task'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'What needs to be done?',
            border: UnderlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                // Task rule verification: Title is single task text, value is automatically 5 coins
                await ref.read(todoCollectionNotifierProvider.notifier).createCollection(
                  text,
                  [text],
                  coinsReward: 5,
                );
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Add Task'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section Header Component
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.primary, letterSpacing: 0.5)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
          child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cs.onPrimaryContainer)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sequential Task Line Item (Line-by-line single row list style)
// ---------------------------------------------------------------------------

class _SingleTaskLineItem extends ConsumerWidget {
  const _SingleTaskLineItem({required this.task});
  final TodoCollection task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final item = task.items.first;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: ListTile(
        leading: Checkbox(
          value: item.isDone,
          onChanged: (_) => ref.read(todoCollectionNotifierProvider.notifier).toggleItem(task.id, item.id, item.isDone),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        title: Text(
          task.title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: item.isDone ? cs.onSurface.withValues(alpha: 0.38) : cs.onSurface,
            decoration: item.isDone ? TextDecoration.lineThrough : TextDecoration.none,
          ),
        ),
        trailing: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            const Icon(Icons.monetization_on_rounded, size: 14, color: Color(0xFFFFA000)),
            Text('+${task.coinsReward}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF8A6000))),
          ],
        ),
        onLongPress: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete Task?'),
              content: Text('Remove "${task.title}" permanently?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
              ],
            ),
          );
          if (confirmed == true) {
            await ref.read(todoCollectionNotifierProvider.notifier).deleteCollection(task.id);
          }
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Collection Card (Google Keep Card Layout)
// ---------------------------------------------------------------------------

class _CollectionCard extends ConsumerWidget {
  const _CollectionCard({required this.collection});
  final TodoCollection collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final notifier = ref.read(todoCollectionNotifierProvider.notifier);

    const maxPreview = 5;
    final preview = collection.items.take(maxPreview).toList();
    final overflow = collection.items.length - maxPreview;

    return Card(
      elevation: 0,
      color:     cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onLongPress:  () => _confirmDelete(context, ref),
        onTap: () => TodoListScreen._openAddEditSheet(context, existingCollection: collection),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                collection.title,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface, letterSpacing: -0.2),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              ...preview.map(
                (item) => _ItemPreviewRow(
                  item:          item,
                  collectionId:  collection.id,
                  onToggle:      () => notifier.toggleItem(collection.id, item.id, item.isDone),
                ),
              ),
              if (overflow > 0) ...[
                const SizedBox(height: 6),
                Text(
                  "+ $overflow more item${overflow > 1 ? 's' : ''}",
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.45)),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.monetization_on_rounded, size: 13, color: Color(0xFFFFA000)),
                  const SizedBox(width: 3),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:    const Text('Delete list?'),
        content: Text('Delete "${collection.title}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(todoCollectionNotifierProvider.notifier).deleteCollection(collection.id);
    }
  }
}

class _ItemPreviewRow extends StatelessWidget {
  const _ItemPreviewRow({required this.item, required this.collectionId, required this.onToggle});
  final TodoItem item;
  final String collectionId;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: item.isDone,
              onChanged: (_) => onToggle(),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              item.text,
              style: TextStyle(
                fontSize: 13,
                color: item.isDone ? cs.onSurface.withValues(alpha: 0.38) : cs.onSurface,
                decoration: item.isDone ? TextDecoration.lineThrough : TextDecoration.none,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Expanding Overlay Floating Action Plus Button Action Sheet
// ---------------------------------------------------------------------------

class _ExpandingSpeedDialFab extends ConsumerStatefulWidget {
  const _ExpandingSpeedDialFab();
  @override
  ConsumerState<_ExpandingSpeedDialFab> createState() => _ExpandingSpeedDialFabState();
}

class _ExpandingSpeedDialFabState extends ConsumerState<_ExpandingSpeedDialFab> {
  bool _isOpen = false;

  void _toggleMenu() => setState(() => _isOpen = !_isOpen);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_isOpen) ...[
          _buildDialOption(
            icon: Icons.check_box_rounded,
            label: 'Create list',
            onTap: () {
              _toggleMenu();
              TodoListScreen._openAddEditSheet(context);
            },
          ),
          const SizedBox(height: 10),
          _buildDialOption(
            icon: Icons.add_task_rounded,
            label: 'Create task',
            onTap: () {
              _toggleMenu();
              TodoListScreen._openAddTaskDialog(context, ref);
            },
          ),
          const SizedBox(height: 14),
        ],
        FloatingActionButton(
          heroTag: 'todo_fab',
          onPressed: _toggleMenu,
          backgroundColor: cs.primaryContainer,
          child: AnimatedRotation(
            turns: _isOpen ? 0.125 : 0.0, // Rotates the plus icon neatly into a close 'x' icon
            duration: const Duration(milliseconds: 200),
            child: Icon(Icons.add_rounded, color: cs.onPrimaryContainer, size: 28),
          ),
        ),
      ],
    );
  }

  Widget _buildDialOption({required IconData icon, required String label, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(label, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 8),
        FloatingActionButton.small(
          onPressed: onTap,
          heroTag: null,
          backgroundColor: theme.colorScheme.surfaceContainerHigh,
          child: Icon(icon, size: 20),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Fallback Empty State Screens
// ---------------------------------------------------------------------------

class _TabEmptyState extends StatelessWidget {
  const _TabEmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38), fontWeight: FontWeight.w500)));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddList, required this.onAddTask});
  final VoidCallback onAddList;
  final VoidCallback onAddTask;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.checklist_rounded, size: 72, color: cs.onSurface.withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          Text('Clear workspace', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.45), fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(onPressed: onAddList, icon:  const Icon(Icons.check_box_rounded), label: const Text('List')),
              const SizedBox(width: 12),
              ElevatedButton.icon(onPressed: onAddTask, icon:  const Icon(Icons.add_task_rounded), label: const Text('Task')),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add / Edit Collection Bottom Sheet Form Factor
// ---------------------------------------------------------------------------

class _AddCollectionSheet extends ConsumerStatefulWidget {
  const _AddCollectionSheet({this.existingCollection});
  final TodoCollection? existingCollection;
  @override
  ConsumerState<_AddCollectionSheet> createState() => _AddCollectionSheetState();
}

class _AddCollectionSheetState extends ConsumerState<_AddCollectionSheet> {
  final _titleController = TextEditingController();
  final _itemControllers = <TextEditingController>[];
  final _titleFocus      = FocusNode();
  bool  _isSaving        = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingCollection != null) {
      final col = widget.existingCollection!;
      _titleController.text = col.title;
      for (final item in col.items) {
        _itemControllers.add(TextEditingController(text: item.text));
      }
    }
    if (_itemControllers.isEmpty) {
      _itemControllers.add(TextEditingController());
      _itemControllers.add(TextEditingController());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _titleFocus.requestFocus());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleFocus.dispose();
    for (final c in _itemControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addItemField() => setState(() => _itemControllers.add(TextEditingController()));

  void _removeItemField(int index) {
    if (_itemControllers.length <= 1) return;
    setState(() {
      _itemControllers[index].dispose();
      _itemControllers.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      _titleFocus.requestFocus();
      return;
    }
    setState(() => _isSaving = true);
    try {
      final texts = _itemControllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();

      if (widget.existingCollection != null) {
        await ref.read(todoCollectionNotifierProvider.notifier).deleteCollection(widget.existingCollection!.id);
      }

      // Hardcoded rule: lists always provide exactly 10 coins reward on completion
      await ref.read(todoCollectionNotifierProvider.notifier).createCollection(
            _titleController.text.trim(),
            texts,
            coinsReward: 10,
          );

      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand:          false,
        initialChildSize: 0.75,
        minChildSize:    0.5,
        maxChildSize:    0.95,
        builder: (ctx, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width:  40,
              height: 4,
              decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(999)),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(widget.existingCollection == null ? 'New List' : 'Edit List',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  TextField(
                    controller:  _titleController,
                    focusNode:   _titleFocus,
                    textCapitalization: TextCapitalization.sentences,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      hintText:    'List title…',
                      hintStyle:   TextStyle(color: cs.onSurface.withValues(alpha: 0.38), fontWeight: FontWeight.w700),
                      border: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('ITEMS', style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.45), letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  for (int i = 0; i < _itemControllers.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(Icons.drag_indicator_rounded, size: 18, color: cs.onSurface.withValues(alpha: 0.28)),
                          const SizedBox(width: 6),
                          Icon(Icons.radio_button_unchecked_rounded, size: 18, color: cs.outline),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _itemControllers[i],
                              textCapitalization: TextCapitalization.sentences,
                              style: theme.textTheme.bodyMedium,
                              decoration: InputDecoration(
                                hintText:  'Add item…',
                                hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.35)),
                                border:    InputBorder.none,
                                isDense:   true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                              onSubmitted: (_) => _addItemField(),
                            ),
                          ),
                          if (_itemControllers.length > 1)
                            GestureDetector(
                              onTap: () => _removeItemField(i),
                              child: Icon(Icons.close_rounded, size: 18, color: cs.onSurface.withValues(alpha: 0.35)),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: _addItemField,
                    icon:  Icon(Icons.add_rounded, color: cs.primary, size: 20),
                    label: Text('Add item', style: TextStyle(color: cs.primary)),
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding:   const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}