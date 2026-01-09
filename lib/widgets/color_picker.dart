import 'package:flutter/material.dart';

class ColorPicker extends StatefulWidget {
  final Color selectedColor;
  final ValueChanged<Color> onColorChanged;
  final List<Color> availableColors;

  const ColorPicker({
    super.key,
    required this.selectedColor,
    required this.onColorChanged,
    this.availableColors = const [
      Colors.black,
      Colors.white,
      Colors.red,
      Colors.yellow,
      Colors.green,
      Colors.blue,
    ],
  });

  @override
  State<ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<ColorPicker> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final color in widget.availableColors)
            GestureDetector(
              onTap: () => widget.onColorChanged(color),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  border: Border.all(
                    color: widget.selectedColor == color 
                      ? Colors.black 
                      : Colors.transparent,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: color == Colors.white
                    ? Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}