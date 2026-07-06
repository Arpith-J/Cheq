// lib/widgets/theme_picker_row.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../providers/custom_theme_provider.dart';

class ThemePickerRow extends ConsumerWidget {
  const ThemePickerRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentColor = ref.watch(customAccentProvider);

    return Wrap(
      spacing: 12.0,
      runSpacing: 12.0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // 1. Generate standard swatches from your provider list
        ...appAccentSwatches.map((color) {
          final isSelected = currentColor == color;
          
          return GestureDetector(
            onTap: () => ref.read(customAccentProvider.notifier).updateAccentColor(color),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: color,
              child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
            ),
          );
        }),
        
        // 2. The Multicoloured Custom Picker Button at the end
        GestureDetector(
          onTap: () => _showColorPickerDialog(context, ref, currentColor),
          child: Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [
                  Colors.red,
                  Colors.yellow,
                  Colors.green,
                  Colors.blue,
                  Colors.purple,
                  Colors.red,
                ],
              ),
            ),
            // Show a checkmark if the current color is NOT in the default list
            child: !appAccentSwatches.contains(currentColor)
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : const Icon(Icons.colorize, color: Colors.white, size: 18),
          ),
        ),
      ],
    );
  }

  // 3. The Custom Color Picker Dialog with Active State Rebuilding
  void _showColorPickerDialog(BuildContext context, WidgetRef ref, Color currentColor) {
    Color pickerColor = currentColor;

    showDialog(
      context: context,
      builder: (context) {
        // 🌟 StatefulBuilder ensures the dialog updates dynamically as you drag your finger
        return StatefulBuilder(
          builder: (context, setStateInDialog) {
            return AlertDialog(
              title: const Text('Pick a custom theme color!'),
              content: SingleChildScrollView(
                child: ColorPicker(
                  pickerColor: pickerColor,
                  onColorChanged: (Color color) {
                    setStateInDialog(() {
                      pickerColor = color;
                    });
                  },
                  pickerAreaHeightPercent: 0.8,
                  enableAlpha: false,
                  displayThumbColor: true,
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  child: const Text('Apply'),
                  onPressed: () {
                    ref.read(customAccentProvider.notifier).updateAccentColor(pickerColor);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
}