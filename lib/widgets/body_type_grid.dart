import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../data/body_types.dart';

class BodyTypeGrid extends StatelessWidget {
  final List<int> selectedCodes;
  final Function(int) onSelected;
  final bool enabled;

  const BodyTypeGrid({
    super.key,
    required this.selectedCodes,
    required this.onSelected,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.2,
      ),
      itemCount: kBodyTypes.length,
      itemBuilder: (context, index) {
        final opt = kBodyTypes[index];
        
        // Multi-select logic: 0 is "Any", others are specific.
        final bool selected = (opt.code == 0 && selectedCodes.isEmpty) || 
                             selectedCodes.contains(opt.code);

        return InkWell(
          onTap: enabled ? () => onSelected(opt.code) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: selected 
                  ? AppTheme.brandPurple.withValues(alpha: 0.1)
                  : AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? AppTheme.brandPurple : AppTheme.borderGrey,
                width: 1.5,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Center(
              child: Text(
                opt.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? AppTheme.brandPurple : AppTheme.white,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
