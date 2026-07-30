import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../models/category_model.dart';
import '../services/firestore_service.dart';
import '../providers/category_provider.dart';

class CategoryManagerSheet extends ConsumerStatefulWidget {
  const CategoryManagerSheet({super.key});

  @override
  ConsumerState<CategoryManagerSheet> createState() => _CategoryManagerSheetState();
}

class _CategoryManagerSheetState extends ConsumerState<CategoryManagerSheet> {
  final TextEditingController _nameController = TextEditingController();
  
  // Track if we are editing an existing category
  String? _editingCategoryId;
  
  final List<Color> _presetColors = [
    Colors.redAccent, 
    Colors.blueAccent, 
    Colors.greenAccent, 
    Colors.orangeAccent, 
    Colors.purpleAccent,
  ];
  
  Color _selectedColor = Colors.blueAccent;

  void _saveCategory() {
    if (_nameController.text.trim().isEmpty) return;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Use the existing ID if editing, otherwise generate a new one
    final newCategory = CategoryModel(
      id: _editingCategoryId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      colorValue: _selectedColor.value,
    );

    FirestoreService.instance.addCategory(user.uid, newCategory);
    
    // Reset the form
    _nameController.clear();
    setState(() {
      _editingCategoryId = null;
      _selectedColor = Colors.blueAccent;
    });
  }

  void _editCategory(CategoryModel category) {
    setState(() {
      _editingCategoryId = category.id;
      _nameController.text = category.name;
      _selectedColor = Color(category.colorValue);
    });
  }

  void _cancelEdit() {
    _nameController.clear();
    setState(() {
      _editingCategoryId = null;
      _selectedColor = Colors.blueAccent;
    });
  }

  void _openColorPicker() {
    Color tempColor = _selectedColor; 

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pick a Custom Color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: _selectedColor,
              onColorChanged: (color) => tempColor = color,
              pickerAreaHeightPercent: 0.8,
              enableAlpha: false, 
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text('Save Color'),
              onPressed: () {
                setState(() => _selectedColor = tempColor);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoryStreamProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom, 
        left: 20, right: 20, top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _editingCategoryId == null ? "Manage Categories" : "Edit Category", 
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)
              ),
              if (_editingCategoryId != null)
                TextButton(
                  onPressed: _cancelEdit,
                  child: const Text("Cancel"),
                )
            ],
          ),
          const SizedBox(height: 20),
          
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    hintText: "Category Name (e.g. Health)",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _saveCategory,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedColor, 
                  foregroundColor: Colors.white
                ),
                child: Text(_editingCategoryId == null ? "Add" : "Save"),
              ),
            ],
          ),
          const SizedBox(height: 15),
          
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _presetColors.length + 1, 
              itemBuilder: (context, index) {
                
                if (index == _presetColors.length) {
                  return GestureDetector(
                    onTap: _openColorPicker,
                    child: Container(
                      width: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade400, width: 2),
                      ),
                      child: const Icon(Icons.colorize_rounded, size: 20),
                    ),
                  );
                }

                final color = _presetColors[index];
                final isSelected = color == _selectedColor;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = color),
                  child: Container(
                    margin: const EdgeInsets.only(right: 10),
                    width: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3) : null,
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 40),

          const Text("Your Categories", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          SizedBox(
            height: 200,
            child: categoriesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text("Error: $err")),
              data: (categories) {
                if (categories.isEmpty) return const Center(child: Text("No categories yet."));
                return ListView.builder(
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    return ListTile(
                      leading: CircleAvatar(backgroundColor: Color(cat.colorValue)),
                      title: Text(cat.name),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_rounded, size: 20),
                            onPressed: () => _editCategory(cat),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                            onPressed: () {
                               final user = FirebaseAuth.instance.currentUser;
                               if (user != null) FirestoreService.instance.deleteCategory(user.uid, cat.id);
                            },
                          ),
                        ],
                      ),
                      onTap: () => _editCategory(cat),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}