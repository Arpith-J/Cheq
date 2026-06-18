// lib/screens/todo_list_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../providers/todo_collection_provider.dart';

// ---------------------------------------------------------------------------
// TodoListScreen
// ---------------------------------------------------------------------------

class TodoListScreen extends ConsumerWidget {
  const TodoListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionsAsync = ref.watch(todoCollectionsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: collectionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text('Error: $e')),
        data:    (collections) => collections.isEmpty
            ? _EmptyState(onAddList: () => _openAddEditSheet(context), onAddTask: () => _openAddTaskDialog(context, ref))
            : _CollectionGrid(collections: collections),
      ),
      floatingActionButton: _GoogleKeepFab(
        onSelectList: () => _openAddEditSheet(context),
        onSelectTask: () => _openAddTaskDialog(context, ref),
      ),
    );
  }

  void _openAddEditSheet(BuildContext context, {TodoCollection? existingCollection}) {
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

  void _openAddTaskDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quick Task'),
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
                await ref.read(todoCollectionNotifierProvider.notifier).createCollection(
                  text,
                  [text], // Creates a collection containing a single item
                  coinsReward: 5,
                );
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Grid
// ---------------------------------------------------------------------------

class _CollectionGrid extends StatelessWidget {
  const _CollectionGrid({required this.collections});

  final List<TodoCollection> collections;

  @override
  Widget build(BuildContext context) {
    return MasonryGridView.count(
      crossAxisCount:  2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      itemCount: collections.length,
      itemBuilder: (ctx, i) => _CollectionCard(collection: collections[i]),
    );
  }
}

// ---------------------------------------------------------------------------
// Collection Card
// ---------------------------------------------------------------------------

class _CollectionCard extends ConsumerWidget {
  const _CollectionCard({required this.collection});

  final TodoCollection collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme  = Theme.of(context);
    final cs     = theme.colorScheme;
    final notifier = ref.read(todoCollectionNotifierProvider.notifier);

    const maxPreview = 5;
    final preview  = collection.items.take(maxPreview).toList();
    final overflow = collection.items.length - maxPreview;

    return Card(
      elevation:    0,
      color:        cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onLongPress:  () => _confirmDelete(context, ref),
        onTap: () {
          // Reuses the identical creation bottom sheet with existing layout models pre-filled
          final state = context.findAncestorStateOfType<ScaffoldState>()?.context ?? context;
          state.findAncestorWidgetOfExactType<TodoListScreen>()?._openAddEditSheet(context, existingCollection: collection);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                collection.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight:    FontWeight.w700,
                  color:         cs.onSurface,
                  letterSpacing: -0.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              ...preview.map(
                (item) => _ItemPreviewRow(
                  item:          item,
                  collectionId:  collection.id,
                  onToggle:      () => notifier.toggleItem(
                    collection.id,
                    item.id,
                    item.isDone,
                  ),
                ),
              ),
              if (overflow > 0) ...[
                const SizedBox(height: 6),
                Text(
                  "+ $overflow more item${overflow > 1 ? 's' : ''}", // Wrapped in double quotes to remove escaping bugs
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.monetization_on_rounded, size: 13, color: Color(0xFFFFA000)),
                  const SizedBox(width: 3),
                  Text(
                    '+${collection.coinsReward} on complete',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF8A6000),
                    ),
                  ),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(todoCollectionNotifierProvider.notifier).deleteCollection(collection.id);
    }
  }
}

// ---------------------------------------------------------------------------
// Single Item Preview Row
// ---------------------------------------------------------------------------

class _ItemPreviewRow extends StatelessWidget {
  const _ItemPreviewRow({
    required this.item,
    required this.collectionId,
    required this.onToggle,
  });

  final TodoItem     item;
  final String       collectionId;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width:  20,
            height: 20,
            child: Checkbox(
              value:           item.isDone,
              onChanged:       (_) => onToggle(),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              item.text,
              style: TextStyle(
                fontSize:      13,
                color:         item.isDone ? cs.onSurface.withValues(alpha: 0.38) : cs.onSurface,
                decoration:    item.isDone ? TextDecoration.lineThrough : TextDecoration.none,
                decorationColor: cs.onSurface.withValues(alpha: 0.38),
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
// Custom Google Keep Split Selection FAB Menu
// ---------------------------------------------------------------------------

class _GoogleKeepFab extends StatelessWidget {
  const _GoogleKeepFab({required this.onSelectList, required this.onSelectTask});

  final VoidCallback onSelectList;
  final VoidCallback onSelectTask;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.check_box_rounded, color: cs.onPrimaryContainer),
            tooltip: 'New List',
            onPressed: onSelectList,
          ),
          Container(width: 1, height: 24, color: cs.onPrimaryContainer.withValues(alpha: 0.2)),
          IconButton(
            icon: Icon(Icons.add_task_rounded, color: cs.onPrimaryContainer),
            tooltip: 'New Task',
            onPressed: onSelectTask,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty State
// ---------------------------------------------------------------------------

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
          Text(
            'Clear workspace',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.45),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: onAddList,
                icon:  const Icon(Icons.check_box_rounded),
                label: const Text('List'),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: onAddTask,
                icon:  const Icon(Icons.add_task_rounded),
                label: const Text('Task'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add / Edit Collection Bottom Sheet
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
  int   _chosenCoins     = 15;

  @override
  void initState() {
    super.initState();
    
    // Check if we are editing an existing list or making a brand new one
    if (widget.existingCollection != null) {
      final col = widget.existingCollection!;
      _titleController.text = col.title;
      _chosenCoins = col.coinsReward;
      
      for (final item in col.items) {
        _itemControllers.add(TextEditingController(text: item.text));
      }
    }
    
    // Fallback defaults if list items are empty
    if (_itemControllers.isEmpty) {
      _itemControllers.add(TextEditingController());
      _itemControllers.add(TextEditingController());
    }

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _titleFocus.requestFocus(),
    );
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
      final texts = _itemControllers
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      if (widget.existingCollection != null) {
        // Edit mode pathing: clear old document entries via structural migration updates
        await ref.read(todoCollectionNotifierProvider.notifier).deleteCollection(widget.existingCollection!.id);
      }

      await ref.read(todoCollectionNotifierProvider.notifier).createCollection(
            _titleController.text.trim(),
            texts,
            coinsReward: _chosenCoins,
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
              decoration: BoxDecoration(
                color:        cs.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
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
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:        cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Completion Reward',
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                            Row(
                              children: [
                                const Icon(Icons.monetization_on_rounded, size: 16, color: Color(0xFFFFA000)),
                                const SizedBox(width: 4),
                                Text('$_chosenCoins Coins',
                                    style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF8A6000))),
                              ],
                            ),
                          ],
                        ),
                        Slider(
                          value:      _chosenCoins.toDouble(),
                          min:        5,
                          max:        50,
                          divisions:  9,
                          label:      '$_chosenCoins',
                          activeColor: const Color(0xFFFFA000),
                          inactiveColor: cs.outlineVariant,
                          onChanged: (val) => setState(() => _chosenCoins = val.toInt()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('ITEMS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:         cs.onSurface.withValues(alpha: 0.45),
                        letterSpacing: 1.2,
                      )),
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