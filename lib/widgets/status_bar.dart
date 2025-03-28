import 'package:flutter/material.dart';

class StatusBar extends StatelessWidget {
  final bool isDark;

  const StatusBar({Key? key, required this.isDark}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Use a lighter, opaque grey for the light theme background
    Color lightThemeBackgroundColor = Colors.grey.shade200; // Lighter opaque grey

    Color backgroundColor = isDark
        ? // Keep existing dark theme logic
          // e.g., Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.8) 
          Theme.of(context).colorScheme.surfaceVariant // Example existing dark theme color
        : lightThemeBackgroundColor; // Use the lighter light theme color

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor, // Apply the determined background color
        borderRadius: BorderRadius.circular(8),
        // Potentially add a subtle border if needed for contrast
        // border: Border.all(color: Colors.grey.shade400, width: 0.5)
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ... existing status bar content (icons, text) ...
        ],
      ),
    );
  }
} 